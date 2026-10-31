"""Prometheus metrics.

Each app instance owns its own ``CollectorRegistry`` so tests are isolated and
nothing leaks between instances. Route labels use the matched route template
(``/api/v1/work``), never the raw URL, to keep label cardinality bounded.
"""

from __future__ import annotations

from dataclasses import dataclass

from prometheus_client import CollectorRegistry, Counter, Gauge, Histogram

LATENCY_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0)


@dataclass(frozen=True)
class Metrics:
    registry: CollectorRegistry
    requests_total: Counter
    request_duration: Histogram
    requests_in_progress: Gauge
    app_info: Gauge
    ready: Gauge
    maintenance: Gauge
    # Only registered when a dependency is configured, so an instance without
    # one never exports a misleading 0 that would trigger the dependency alert.
    dependency_up: Gauge | None


def build_metrics(
    service: str, version: str, environment: str, *, dependency_configured: bool = False
) -> Metrics:
    registry = CollectorRegistry()
    app_info = Gauge(
        "app_info",
        "Static information about the running build.",
        ["service", "version", "environment"],
        registry=registry,
    )
    app_info.labels(service, version, environment).set(1)
    return Metrics(
        registry=registry,
        requests_total=Counter(
            "http_requests_total",
            "HTTP requests handled, by method, route template and status code.",
            ["method", "route", "status"],
            registry=registry,
        ),
        request_duration=Histogram(
            "http_request_duration_seconds",
            "HTTP request latency in seconds, by method and route template.",
            ["method", "route"],
            buckets=LATENCY_BUCKETS,
            registry=registry,
        ),
        requests_in_progress=Gauge(
            "http_requests_in_progress",
            "HTTP requests currently being handled.",
            registry=registry,
        ),
        app_info=app_info,
        ready=Gauge("app_ready", "1 when the instance reports ready.", registry=registry),
        maintenance=Gauge(
            "app_maintenance_mode", "1 when maintenance mode is enabled.", registry=registry
        ),
        dependency_up=(
            Gauge(
                "app_dependency_up",
                "1 when the configured downstream dependency answered its last check.",
                registry=registry,
            )
            if dependency_configured
            else None
        ),
    )
