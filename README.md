# cloud-platform-automation

Platform engineering project: a small Python service packaged, deployed, probed and observed the way production services are.

> **Status:** the service and its container are in place. Kubernetes manifests, Terraform for Azure, monitoring and full documentation follow in later pull requests.

## Platform API

A FastAPI service whose job is to behave correctly on a platform:

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Liveness: process and event loop alive. Never checks dependencies, so a downstream outage cannot cause a restart storm. |
| `GET /readyz` | Readiness: false while warming up, draining on shutdown, in maintenance mode, or when the configured dependency is down. |
| `GET /metrics` | Prometheus metrics: request count and latency by route template, in-flight requests, readiness, build info. |
| `GET /api/v1/info` | Build and instance information. |
| `GET /api/v1/work?ms=N` | Bounded synthetic latency, for load and rollout tests. |
| `POST /api/v1/admin/maintenance` | Bearer-token protected; takes the instance out of rotation without a restart. |

Configuration is validated at startup (`APP_*` environment variables). In `prod`, a strong admin token and JSON logs are mandatory, and fault injection is forbidden.

## Run locally

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt && pip install --no-deps -e .
pytest --cov
uvicorn platform_api.main:create_app --factory --port 8080
```

```bash
docker build -t platform-api:local .
docker run --rm -p 8080:8080 --read-only --cap-drop ALL platform-api:local
```

## Licence

[MIT](LICENSE)
