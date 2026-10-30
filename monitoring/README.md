# Monitoring

Prometheus scrapes the API, evaluates recording and alerting rules, and feeds a provisioned Grafana dashboard. Everything runs locally with Docker Compose.

```bash
docker compose -f monitoring/docker-compose.yml up -d --build
docker compose -f monitoring/docker-compose.yml --profile load up -d loadgen   # optional traffic
./scripts/verify-monitoring.sh                                                  # smoke test
```

| URL | What |
|---|---|
| http://localhost:8080/metrics | raw metrics from the API |
| http://localhost:9090/alerts | alert states (inactive / pending / firing) |
| http://localhost:3000/d/platform-api | Grafana dashboard (anonymous read-only viewer) |

All ports bind to `127.0.0.1` only. Set `GRAFANA_ADMIN_PASSWORD` to change the local admin password.

## Metrics exposed by the API

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `http_requests_total` | counter | method, route, status | requests handled; `route` is the route **template**, unmatched paths are `unmatched` |
| `http_request_duration_seconds` | histogram | method, route | latency, buckets 5 ms – 5 s |
| `http_requests_in_progress` | gauge | — | requests in flight |
| `app_ready` | gauge | — | 1 when ready; computed at scrape time, so it is right even when nothing calls `/readyz` |
| `app_maintenance_mode` | gauge | — | 1 while taken out of rotation |
| `app_dependency_up` | gauge | — | only exported when `APP_DEPENDENCY_URL` is set |
| `app_info` | gauge | service, version, environment | build information |

## Rules

Recording rules (probe and scrape routes excluded):

| Rule | Definition |
|---|---|
| `job:http_requests:rate5m` | application requests per second |
| `job:http_request_errors:ratio_rate5m` | 5xx ÷ all requests; an explicit `0` when nothing failed, `NaN` when there is no traffic at all |
| `job:http_request_duration_seconds:p95_5m` | p95 latency |

Alerts:

| Alert | Condition | For | Severity |
|---|---|---|---|
| `PlatformApiDown` | scrape target down | 1m | critical |
| `PlatformApiHighErrorRate` | 5xx ratio > 5% | 5m | critical |
| `PlatformApiHighLatency` | p95 > 500 ms | 10m | warning |
| `PlatformApiNotReady` | `app_ready == 0` | 5m | warning |
| `PlatformApiDependencyDown` | `app_dependency_up == 0` | 5m | warning |
| `PlatformApiMaintenanceModeLeftOn` | maintenance on | 30m | info |

`monitoring/prometheus/alerts.test.yml` unit-tests these with `promtool test rules`, using synthetic series. The tests check that each alert fires only after its `for` duration, that its annotations render correctly, that probe errors are excluded from the error ratio, and that the ratio is an explicit 0 when nothing fails.

```bash
docker run --rm -v "$PWD/monitoring/prometheus:/p" -w /p --entrypoint promtool prom/prometheus:v3.5.0 test rules alerts.test.yml
```

## Dashboard

`grafana/dashboards/platform-api.json` is provisioned read-only (changes belong in Git). Panels: request rate, 5xx ratio, p95 latency, ready instances, requests by route and status, p50/p95/p99 latency, in-flight requests, readiness/maintenance/dependency state, scrape health and running builds.

## Defects found by running the stack

Unit tests passed, but running the real stack exposed three defects. Each is fixed in this change and covered by a test:

1. **`app_ready` read 0 on a healthy instance**, because it was only updated when `/readyz` was called. Kubernetes probes would have hidden this; any other environment would have fired `PlatformApiNotReady`. The gauge is now computed at scrape time.
2. **`PlatformApiDependencyDown` went pending on an instance with no dependency**, because the gauge defaulted to 0. It is now only exported when a dependency is configured.
3. **The error-ratio rule returned no data when nothing failed**, so the dashboard showed "No data" instead of 0%. It now returns an explicit 0.

## In Kubernetes

The Deployment carries `prometheus.io/scrape`, `port` and `path` annotations, and the NetworkPolicy admits scrapes from the `monitoring` namespace. With the Prometheus Operator you would add a `ServiceMonitor` and load `alerts.yml` as a `PrometheusRule`. On AKS, Container Insights (enabled by Terraform) collects node and pod metrics and logs. Alertmanager routing (email, Slack, PagerDuty) is not configured here.
