from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Iterator

import httpx
import pytest
from fastapi.testclient import TestClient

from platform_api.config import Settings
from platform_api.main import create_app

TOKEN = "s3cure-admin-token-value"


def client_for(**overrides: object) -> TestClient:
    settings = Settings(**{"log_format": "text", **overrides})  # type: ignore[arg-type]
    return TestClient(create_app(settings))


@pytest.fixture
def client() -> Iterator[TestClient]:
    with client_for() as c:
        yield c


def test_liveness_is_always_ok(client: TestClient) -> None:
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_after_startup(client: TestClient) -> None:
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json()["ready"] is True


def test_not_ready_while_warming_up_but_still_live() -> None:
    with client_for(startup_delay_s=30) as c:
        ready = c.get("/readyz")
        assert ready.status_code == 503
        assert ready.json()["reasons"] == ["started"]
        assert c.get("/healthz").status_code == 200


def test_fault_injection_keeps_instance_unready() -> None:
    with client_for(fail_readiness=True) as c:
        response = c.get("/readyz")
        assert response.status_code == 503
        assert "fault_injection_off" in response.json()["reasons"]


def test_readiness_turns_off_when_draining() -> None:
    app = create_app(Settings(log_format="text"))
    with TestClient(app) as c:
        assert c.get("/readyz").status_code == 200
    # After the lifespan has exited the app is draining.
    assert app.state.platform.draining is True
    report = asyncio.run(_readiness_of(app))
    assert report.ready is False and "not_draining" in report.reasons


async def _readiness_of(app):  # type: ignore[no-untyped-def]
    from platform_api.main import _readiness

    return await _readiness(app.state.platform)


def _client_with_dependency(handler: httpx.MockTransport) -> TestClient:
    settings = Settings(log_format="text", dependency_url="http://inventory.internal/health")  # type: ignore[arg-type]
    return TestClient(create_app(settings, http_client=httpx.AsyncClient(transport=handler)))


def test_dependency_up_and_down() -> None:
    healthy = httpx.MockTransport(lambda request: httpx.Response(200))
    with _client_with_dependency(healthy) as c:
        body = c.get("/readyz").json()
        assert body["ready"] is True and body["checks"]["dependency"] is True
        assert "app_dependency_up 1.0" in c.get("/metrics").text

    failing = httpx.MockTransport(lambda request: httpx.Response(503))
    with _client_with_dependency(failing) as c:
        response = c.get("/readyz")
        assert response.status_code == 503
        assert response.json()["reasons"] == ["dependency"]

    def refuse(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused", request=request)

    with _client_with_dependency(httpx.MockTransport(refuse)) as c:
        assert c.get("/readyz").status_code == 503
        assert "app_dependency_up 0.0" in c.get("/metrics").text


def test_dependency_outage_does_not_fail_liveness() -> None:
    def refuse(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused", request=request)

    with _client_with_dependency(httpx.MockTransport(refuse)) as c:
        assert c.get("/healthz").status_code == 200


def test_info_reports_build(client: TestClient) -> None:
    body = client.get("/api/v1/info").json()
    assert body["service"] == "platform-api"
    assert body["version"] == "1.0.0"
    assert body["environment"] == "dev"
    assert body["instance"]


def test_work_endpoint_validates_bounds() -> None:
    with client_for(max_work_ms=100) as c:
        assert c.get("/api/v1/work", params={"ms": 5}).json() == {"slept_ms": 5}
        assert c.get("/api/v1/work", params={"ms": 101}).status_code == 422
        assert c.get("/api/v1/work", params={"ms": -1}).status_code == 422
        assert c.get("/api/v1/work", params={"ms": "abc"}).status_code == 422


def test_metrics_use_route_templates_not_raw_paths(client: TestClient) -> None:
    client.get("/api/v1/work", params={"ms": 1})
    client.get("/api/v1/work", params={"ms": 2})
    client.get("/does-not-exist/123")
    text = client.get("/metrics").text
    assert 'http_requests_total{method="GET",route="/api/v1/work",status="200"} 2.0' in text
    assert 'route="unmatched",status="404"' in text
    assert "/does-not-exist/123" not in text
    assert (
        'http_request_duration_seconds_bucket{le="0.005",method="GET",route="/api/v1/work"}' in text
    )
    assert 'app_info{environment="dev",service="platform-api",version="1.0.0"} 1.0' in text


def test_request_id_is_propagated_or_generated(client: TestClient) -> None:
    echoed = client.get("/healthz", headers={"X-Request-ID": "abc-123"})
    assert echoed.headers["X-Request-ID"] == "abc-123"
    generated = client.get("/healthz").headers["X-Request-ID"]
    assert len(generated) == 32


def test_admin_endpoint_disabled_without_token(client: TestClient) -> None:
    response = client.post("/api/v1/admin/maintenance", json={"enabled": True})
    assert response.status_code == 404


def test_admin_requires_valid_bearer_token() -> None:
    with client_for(admin_token=TOKEN) as c:
        url = "/api/v1/admin/maintenance"
        assert c.post(url, json={"enabled": True}).status_code == 401
        wrong = {"Authorization": "Bearer wrong"}
        assert c.post(url, json={"enabled": True}, headers=wrong).status_code == 401
        assert c.get("/readyz").status_code == 200


def test_maintenance_mode_removes_instance_from_rotation() -> None:
    auth = {"Authorization": f"Bearer {TOKEN}"}
    with client_for(admin_token=TOKEN) as c:
        url = "/api/v1/admin/maintenance"
        assert c.post(url, json={"enabled": True}, headers=auth).json() == {"maintenance": True}
        response = c.get("/readyz")
        assert response.status_code == 503
        assert response.json()["reasons"] == ["not_in_maintenance"]
        assert c.get("/healthz").status_code == 200  # live, just not taking traffic
        assert "app_maintenance_mode 1.0" in c.get("/metrics").text
        c.post(url, json={"enabled": False}, headers=auth)
        assert c.get("/readyz").status_code == 200


def test_unhandled_errors_return_json_with_request_id() -> None:
    app = create_app(Settings(log_format="text"))

    @app.get("/boom")
    async def boom() -> None:
        raise RuntimeError("kaboom")

    with TestClient(app, raise_server_exceptions=False) as c:
        response = c.get("/boom", headers={"X-Request-ID": "req-1"})
        assert response.status_code == 500
        assert response.json() == {"detail": "internal server error", "request_id": "req-1"}
        assert 'route="/boom",status="500"' in c.get("/metrics").text


def test_docs_disabled_in_production() -> None:
    with client_for(environment="prod", admin_token=TOKEN, log_format="json") as c:
        assert c.get("/docs").status_code == 404
    with client_for() as c:
        assert c.get("/docs").status_code == 200


def test_json_logs_include_request_context(capsys: pytest.CaptureFixture[str]) -> None:
    with TestClient(create_app(Settings(log_format="json"))) as c:
        c.get("/api/v1/info", headers={"X-Request-ID": "trace-42"})
    lines = [json.loads(line) for line in capsys.readouterr().out.splitlines() if line.strip()]
    request_logs = [r for r in lines if r["event"] == "request"]
    assert request_logs[0]["request_id"] == "trace-42"
    assert request_logs[0]["route"] == "/api/v1/info"
    assert request_logs[0]["status"] == 200
    assert request_logs[0]["service"] == "platform-api"
    logging.getLogger().handlers.clear()


def test_uvicorn_logs_use_the_structured_formatter() -> None:
    create_app(Settings(log_format="json"))
    server_logger = logging.getLogger("uvicorn.error")
    assert server_logger.handlers == []
    assert server_logger.propagate is True
    assert logging.getLogger("uvicorn.access").disabled is True
    logging.getLogger().handlers.clear()


def test_ready_metric_is_correct_without_probe_traffic() -> None:
    auth = {"Authorization": f"Bearer {TOKEN}"}
    with client_for(admin_token=TOKEN) as c:
        # No call to /readyz: the gauge must still reflect the real state.
        assert "app_ready 1.0" in c.get("/metrics").text
        c.post("/api/v1/admin/maintenance", json={"enabled": True}, headers=auth)
        assert "app_ready 0.0" in c.get("/metrics").text
    with client_for(startup_delay_s=30) as c:
        assert "app_ready 0.0" in c.get("/metrics").text


def test_ready_metric_waits_for_first_dependency_check() -> None:
    healthy = httpx.MockTransport(lambda request: httpx.Response(200))
    with _client_with_dependency(healthy) as c:
        assert "app_ready 0.0" in c.get("/metrics").text  # unknown until checked
        c.get("/readyz")
        assert "app_ready 1.0" in c.get("/metrics").text


def test_dependency_metric_only_exported_when_configured(client: TestClient) -> None:
    assert "app_dependency_up" not in client.get("/metrics").text
