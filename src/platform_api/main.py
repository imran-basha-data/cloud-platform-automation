"""FastAPI application factory.

Probe semantics (what Kubernetes relies on):

* ``/healthz`` (liveness): the process is running and the event loop responds.
  It never checks dependencies, because restarting a pod does not fix a
  downstream outage and would only cause a restart storm.
* ``/readyz`` (readiness): the instance should receive traffic. False while
  warming up, while draining on shutdown, in maintenance mode, or when the
  configured dependency is unreachable.
"""

import asyncio
import hmac
import logging
import socket
import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Annotated, Any

import httpx
from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel

from platform_api.config import Settings
from platform_api.logging_config import configure_logging, request_id_var
from platform_api.metrics import Metrics, build_metrics

log = logging.getLogger("platform_api")
PROBE_PATHS = frozenset({"/healthz", "/readyz", "/metrics"})


@dataclass
class AppState:
    settings: Settings
    metrics: Metrics
    http_client: httpx.AsyncClient
    started: bool = False
    draining: bool = False
    maintenance: bool = False
    # Result of the most recent dependency check; None until the first check.
    dependency_ok: bool | None = None
    started_monotonic: float = field(default_factory=time.monotonic)

    def local_checks(self) -> dict[str, bool]:
        """Readiness conditions that need no I/O."""
        return {
            "started": self.started,
            "not_draining": not self.draining,
            "not_in_maintenance": not self.maintenance,
            "fault_injection_off": not self.settings.fail_readiness,
        }

    def is_ready_for_metrics(self) -> float:
        """Readiness as seen at scrape time, using the last dependency result."""
        dependency = self.settings.dependency_url is None or self.dependency_ok is True
        return 1.0 if dependency and all(self.local_checks().values()) else 0.0


class ReadinessReport(BaseModel):
    ready: bool
    checks: dict[str, bool]
    reasons: list[str]


class MaintenanceRequest(BaseModel):
    enabled: bool


def create_app(
    settings: Settings | None = None,
    http_client: httpx.AsyncClient | None = None,
) -> FastAPI:
    settings = settings or Settings()
    configure_logging(
        settings.log_level,
        settings.log_format,
        settings.name,
        settings.environment,
        settings.version,
    )
    metrics = build_metrics(
        settings.name,
        settings.version,
        settings.environment,
        dependency_configured=settings.dependency_url is not None,
    )
    state = AppState(
        settings=settings,
        metrics=metrics,
        http_client=http_client or httpx.AsyncClient(timeout=settings.dependency_timeout_s),
    )
    # Evaluated on every scrape, so the metric is correct even when nothing
    # calls /readyz (e.g. outside Kubernetes).
    metrics.ready.set_function(state.is_ready_for_metrics)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        warmup: asyncio.Task[None] | None = None
        if settings.startup_delay_s > 0:
            warmup = asyncio.create_task(_warm_up(state, settings.startup_delay_s))
        else:
            state.started = True
        log.info("startup", extra={"fields": {"startup_delay_s": settings.startup_delay_s}})
        try:
            yield
        finally:
            # Stop advertising readiness first so load balancers drain this pod.
            state.draining = True
            if warmup is not None:
                warmup.cancel()
            await state.http_client.aclose()
            log.info("shutdown")

    app = FastAPI(
        title="Platform API",
        version=settings.version,
        lifespan=lifespan,
        docs_url="/docs" if settings.environment != "prod" else None,
        redoc_url=None,
    )
    app.state.platform = state

    @app.middleware("http")
    async def observe(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        token = request_id_var.set(request_id[:64])
        metrics.requests_in_progress.inc()
        start = time.perf_counter()
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
        except Exception:
            log.exception("unhandled_error")
            response = JSONResponse(
                {"detail": "internal server error", "request_id": request_id},
                status_code=500,
            )
        finally:
            elapsed = time.perf_counter() - start
            route = _route_template(request)
            metrics.requests_in_progress.dec()
            metrics.requests_total.labels(request.method, route, str(status_code)).inc()
            metrics.request_duration.labels(request.method, route).observe(elapsed)
            level = logging.DEBUG if request.url.path in PROBE_PATHS else logging.INFO
            log.log(
                level,
                "request",
                extra={
                    "fields": {
                        "method": request.method,
                        "route": route,
                        "status": status_code,
                        "duration_ms": round(elapsed * 1000, 2),
                    }
                },
            )
            request_id_var.reset(token)
        response.headers["X-Request-ID"] = request_id[:64]
        return response

    @app.get("/healthz", tags=["probes"])
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz", tags=["probes"], response_model=ReadinessReport)
    async def readyz(response: Response) -> ReadinessReport:
        report = await _readiness(state)
        if not report.ready:
            response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return report

    @app.get("/metrics", tags=["probes"], include_in_schema=False)
    async def prometheus_metrics() -> Response:
        return Response(generate_latest(metrics.registry), media_type=CONTENT_TYPE_LATEST)

    @app.get("/api/v1/info", tags=["api"])
    async def info() -> dict[str, Any]:
        return {
            "service": settings.name,
            "version": settings.version,
            "environment": settings.environment,
            "instance": socket.gethostname(),
            "uptime_s": round(time.monotonic() - state.started_monotonic, 1),
        }

    @app.get("/api/v1/work", tags=["api"])
    async def work(ms: Annotated[int, Query(ge=0)] = 50) -> dict[str, int]:
        """Simulate a request that takes ``ms`` milliseconds (load-test target)."""
        if ms > settings.max_work_ms:
            raise HTTPException(status_code=422, detail=f"ms must be <= {settings.max_work_ms}")
        await asyncio.sleep(ms / 1000)
        return {"slept_ms": ms}

    bearer = HTTPBearer(auto_error=False)

    async def require_admin(
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    ) -> None:
        if settings.admin_token is None:
            raise HTTPException(status_code=404, detail="Not Found")
        expected = settings.admin_token.get_secret_value().encode()
        supplied = (credentials.credentials if credentials else "").encode()
        if not hmac.compare_digest(supplied, expected):
            raise HTTPException(
                status_code=401,
                detail="invalid or missing bearer token",
                headers={"WWW-Authenticate": "Bearer"},
            )

    @app.post(
        "/api/v1/admin/maintenance",
        tags=["admin"],
        dependencies=[Depends(require_admin)],
    )
    async def set_maintenance(body: MaintenanceRequest) -> dict[str, bool]:
        """Take this instance out of (or back into) rotation without restarting it."""
        state.maintenance = body.enabled
        metrics.maintenance.set(1 if body.enabled else 0)
        log.warning("maintenance_mode_changed", extra={"fields": {"enabled": body.enabled}})
        return {"maintenance": state.maintenance}

    return app


async def _warm_up(state: AppState, delay_s: float) -> None:
    await asyncio.sleep(delay_s)
    state.started = True
    log.info("warm_up_complete", extra={"fields": {"delay_s": delay_s}})


async def _readiness(state: AppState) -> ReadinessReport:
    checks = state.local_checks()
    if state.settings.dependency_url is not None:
        checks["dependency"] = await _dependency_ok(state)
    reasons = [name for name, ok in checks.items() if not ok]
    return ReadinessReport(ready=not reasons, checks=checks, reasons=reasons)


async def _dependency_ok(state: AppState) -> bool:
    url = str(state.settings.dependency_url)
    try:
        response = await state.http_client.get(url, timeout=state.settings.dependency_timeout_s)
        ok = response.status_code < 500
    except httpx.HTTPError as exc:
        log.warning("dependency_unreachable", extra={"fields": {"error": type(exc).__name__}})
        ok = False
    state.dependency_ok = ok
    if state.metrics.dependency_up is not None:
        state.metrics.dependency_up.set(1 if ok else 0)
    return ok


def _route_template(request: Request) -> str:
    route = request.scope.get("route")
    path = getattr(route, "path", None)
    return path if isinstance(path, str) else "unmatched"
