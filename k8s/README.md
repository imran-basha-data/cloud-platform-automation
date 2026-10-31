# Kubernetes deployment

Kustomize base plus two overlays:

| Path | Namespace | Replicas | Notes |
|---|---|---|---|
| `base/` | — | 2 | Deployment, Service, HPA, PDB, NetworkPolicy, ServiceAccount, generated ConfigMap |
| `overlays/dev/` | `platform-dev` | 2 (HPA 2–6) | `APP_ENVIRONMENT=dev`, debug logging, admin Secret optional |
| `overlays/prod/` | `platform-prod` | 3 (HPA 3–12) | admin Secret **required**, larger requests/limits, zone spreading, `imagePullPolicy: Always`, PDB `minAvailable: 2` |

Both namespaces enforce the **restricted** Pod Security Standard.

## What the manifests guarantee

| Concern | Setting |
|---|---|
| Zero-downtime rollouts | `maxUnavailable: 0`, `maxSurge: 1`, `minReadySeconds: 5`, readiness gates traffic |
| Failed rollouts are detected | `progressDeadlineSeconds: 90` marks the Deployment `ProgressDeadlineExceeded` |
| Slow starts do not cause restart loops | `startupProbe` allows up to 60 s before liveness applies |
| Graceful shutdown | `preStop: sleep 5` lets endpoint removal propagate; the app stops reporting ready on SIGTERM and uvicorn drains for up to 20 s within the 30 s grace period |
| Config changes roll out | `configMapGenerator` adds a content hash to the ConfigMap name |
| Least privilege | non-root uid 10001, read-only root FS, all capabilities dropped, no privilege escalation, `RuntimeDefault` seccomp, no service-account token |
| Bounded resources | requests and limits on every container |
| Availability during maintenance | PodDisruptionBudget; topology spread across nodes (and zones in prod) |
| Network exposure | ingress allowed only from the same namespace and the `monitoring` namespace |

## Deploy

```bash
# 1. Secret (never committed). In AKS prefer the Key Vault CSI driver or External Secrets.
kubectl create namespace platform-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl -n platform-dev create secret generic platform-api-secrets \
  --from-literal=admin-token="$(openssl rand -hex 24)"

# 2. Apply and wait.
kubectl apply -k k8s/overlays/dev
kubectl -n platform-dev rollout status deployment/platform-api --timeout=180s
```

For prod, set the image registry in `overlays/prod/kustomization.yaml` from the Terraform output `acr_login_server`, and set the release tag (never `latest`).

## Roll out a new version

```bash
kubectl -n platform-dev set image deployment/platform-api api=<registry>/platform-api:<new-tag>
kubectl -n platform-dev rollout status deployment/platform-api --timeout=180s
```

Or change `images[].newTag` in the overlay and `kubectl apply -k`, which is the GitOps-friendly path.

## Rollback procedure

1. **Detect.** `rollout status` exits non-zero, or the Deployment shows `Progressing=False, reason=ProgressDeadlineExceeded`:
   ```bash
   kubectl -n platform-dev get deployment platform-api \
     -o jsonpath='{.status.conditions[?(@.type=="Progressing")]}'
   ```
   With `maxUnavailable: 0`, the previous ReplicaSet keeps serving at full capacity while the new pods fail readiness.
2. **Inspect.**
   ```bash
   kubectl -n platform-dev rollout history deployment/platform-api
   kubectl -n platform-dev describe deployment platform-api
   kubectl -n platform-dev logs -l app.kubernetes.io/component=api --prefix --tail=100
   ```
3. **Roll back** to the previous revision (or a specific one with `--to-revision=N`):
   ```bash
   kubectl -n platform-dev rollout undo deployment/platform-api
   kubectl -n platform-dev rollout status deployment/platform-api --timeout=180s
   ```
4. **Make Git match.** If the bad change came from a commit, revert it, so the next `apply -k` does not re-introduce it.

`scripts/k8s-e2e.sh` runs exactly this sequence in CI against a kind cluster. It releases a version that never becomes ready, asserts the rollout is reported as failed while full capacity keeps serving, then undoes it.

## Take one pod out of rotation without restarting it

```bash
TOKEN=$(kubectl -n platform-dev get secret platform-api-secrets -o jsonpath='{.data.admin-token}' | base64 -d)
kubectl -n platform-dev port-forward pod/<pod-name> 8080:8080 &
curl -X POST localhost:8080/api/v1/admin/maintenance \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"enabled": true}'
```

The pod fails readiness, leaves the Service endpoints, and keeps running for debugging.

## Autoscaling

The HPA targets 70% CPU and needs `metrics-server` (installed by default on AKS). Scale-down is damped with a 5-minute stabilisation window and at most one pod per minute. The CI cluster has no metrics-server, so the HPA there is validated for schema only; scaling behaviour is not exercised in CI.
