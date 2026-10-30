# Troubleshooting

## The app refuses to start

Startup validation failed. The log shows the reason, for example:

```text
pydantic_core._pydantic_core.ValidationError: APP_ADMIN_TOKEN must be set (16+ characters) in prod
```

Set the variable (prod requires `APP_ADMIN_TOKEN`, JSON logs and no fault injection) or fix the invalid value.

## Pod is Running but not Ready

```bash
kubectl -n platform-dev exec deploy/platform-api -- python -c \
  "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/readyz').read())"
```

The `reasons` list names the failing check:

| Reason | Meaning | Action |
|---|---|---|
| `started` | still warming up | wait; check `APP_STARTUP_DELAY_S` |
| `not_in_maintenance` | maintenance mode on | disable via the admin endpoint |
| `fault_injection_off` | `APP_FAIL_READINESS=true` | remove the variable (see the rollback runbook) |
| `dependency` | `APP_DEPENDENCY_URL` unreachable or returning 5xx | fix the dependency; the pod stays alive by design |

## Rollout stuck

`kubectl rollout status` times out, or the Deployment shows `ProgressDeadlineExceeded`. Old pods keep serving because of `maxUnavailable: 0`. Follow the [rollback procedure](../k8s/README.md#rollback-procedure).

## Pods rejected by the namespace

`violates PodSecurity "restricted:latest"` means a container lacks `runAsNonRoot`, `allowPrivilegeEscalation: false`, `drop: [ALL]` or a seccomp profile. Copy the securityContext from `k8s/base/deployment.yaml`.

## HPA shows `<unknown>` targets

`metrics-server` is missing. AKS has it by default; on kind, install it separately.

## Prometheus target down

- Compose: `docker compose -f monitoring/docker-compose.yml ps` to check the `api` container is healthy.
- Kubernetes: the NetworkPolicy only admits scrapes from a namespace labelled `kubernetes.io/metadata.name: monitoring`.

## Error ratio panel shows NaN

There is no traffic in the window (0 ÷ 0). It becomes 0 once requests flow.

## `PlatformApiDependencyDown` firing

The configured dependency hasn't answered for 5 minutes. Check `APP_DEPENDENCY_URL` and the network path. The alert can't fire on instances without a dependency, because the metric isn't exported there.

## Terraform

| Symptom | Cause / fix |
|---|---|
| `prod requires authorized_ip_ranges` | set `authorized_ip_ranges` in `prod.tfvars` |
| encryption at host error on apply | `az feature register --namespace Microsoft.Compute --name EncryptionAtHost`, then re-register the provider |
| `terraform test` fails offline | it needs to download the azurerm provider on first `init` |

## Docker build fails with `CERTIFICATE_VERIFY_FAILED`

You are behind a TLS-intercepting proxy:

```bash
docker build --secret id=ca_bundle,src=/path/to/ca.pem -t platform-api:local .
```
