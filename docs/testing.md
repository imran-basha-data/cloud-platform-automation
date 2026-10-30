# Testing

## CI jobs

| Job | What it runs | What it proves |
|---|---|---|
| App lint, types and tests | ruff, ruff format, mypy (strict), pytest with a 90% coverage gate, no-skip check | service behaviour |
| Container build, health and scan | build; uid ≠ 0; `--read-only --cap-drop ALL` start; Docker health `healthy`; `/readyz`, `/metrics`; SIGTERM exit 0 with shutdown log; Trivy (fails on fixable HIGH/CRITICAL) | the image is safe and operable |
| Dependency, code and secret scanning | bandit, pip-audit `--strict`, gitleaks (full history) | no known-vulnerable deps, risky code or leaked secrets |
| Kubernetes manifest validation | `kubectl kustomize` dev + prod, kubeconform `-strict` (k8s 1.33), shellcheck | manifests are schema-valid |
| Kubernetes reliability tests (kind) | `scripts/k8s-e2e.sh` | rollout, rollback, readiness and self-healing behave as designed |
| Terraform fmt, validate and tests | fmt, `init -backend=false`, validate, `terraform test` | Terraform is valid and its logic and guardrails are correct |
| IaC security scan (Checkov) | Terraform, rendered overlays, Dockerfile | security posture; every exception is justified in code |
| Monitoring | promtool config check + rule tests, dashboard lint, Compose stack + smoke test | alerts fire correctly; stack works end to end |

CI fails if any pytest test is skipped, so a missing dependency can't masquerade as a pass.

## Unit tests (32)

`tests/test_api.py` and `tests/test_config.py` cover:

- liveness always OK, including during a dependency outage
- readiness transitions: warm-up, draining after shutdown, maintenance, fault injection, dependency up / 5xx / connection refused
- metrics: route templates (no raw paths), `unmatched` for 404s, histogram buckets, build info, readiness computed without probe traffic, dependency gauge only when configured
- request ID echo and generation; JSON log fields; uvicorn logs routed through the formatter
- admin auth: disabled without a token, 401 on missing or wrong token, constant-time comparison
- unhandled errors return JSON with the request ID and are counted as 500
- config: env loading, invalid values fail fast, production guardrails, secret masking

## Kubernetes scenarios (kind)

Latest recorded run (CI, kindest/node v1.33.1):

```text
PASS: v1 deployed and serving through the Service
traffic during rollout: {"ok": 833, "failed": 0, "versions": {"1.0.0": 278, "1.1.0": 555}}
PASS: rolling update completed with 0 failed requests
PASS: bad rollout stalled with full capacity (2/2) still serving v2
PASS: rollout undo restored v2
PASS: ready endpoints went 2 -> 1 without restarting the pod
PASS: deleted pod replaced; 2 api pods running
```

These ran only in CI. In the development sandbox, pods couldn't start inside nested containers, so locally the manifests were validated with a server-side dry run against a real API server (including Pod Security admission) instead.

## Terraform tests (14)

`terraform/tests/*.tftest.hcl` with a mocked azurerm provider:

- the root module wires identities and roles correctly (AcrPull → kubelet, Managed Identity Operator → control plane, Key Vault Secrets User → workload identity, federated subject)
- prod passes with guardrails satisfied
- rejected: prod without IP restrictions, prod without the SLA tier, min > max nodes, unknown environment, invalid CIDR, region outside the allow-list, ACR name with a hyphen, AKS subnet smaller than /24
- module security settings: AKS local accounts off, Azure RBAC, workload identity, network policy, autoscaling, API IP restriction, patch upgrades, system pool for add-ons only, encrypted user pool; ACR without admin or anonymous access, Premium private and zone-redundant; Key Vault RBAC, purge protection, default-deny firewall

## Alert rule tests

`monitoring/prometheus/alerts.test.yml` (promtool): target-down timing, 10% error ratio fires the critical alert, probe 503s excluded, explicit 0 ratio, not-ready after 5 minutes, p95 above 500 ms fires after 10 minutes, with exact rendered annotations.

## Run everything locally

```bash
pytest --cov
docker build -t platform-api:local .
docker run --rm -v "$PWD/monitoring/prometheus:/p" -w /p --entrypoint promtool prom/prometheus:v3.5.0 test rules alerts.test.yml
docker compose -f monitoring/docker-compose.yml up -d --build && ./scripts/verify-monitoring.sh
(cd terraform && terraform init -backend=false && terraform validate && terraform test)
# kind scenarios: see README quick start
```
