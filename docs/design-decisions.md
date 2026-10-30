# Design decisions

## 1. Liveness never checks dependencies

**Decision:** `/healthz` only proves the process responds; dependencies feed `/readyz` only.

**Why:** if liveness checked a shared database, one database outage would make Kubernetes restart every pod at once, turning a degraded service into a dead one. Readiness takes pods out of rotation without killing them.

## 2. `maxUnavailable: 0`, `maxSurge: 1`

**Decision:** add one new pod at a time and never remove an old one until a new one is ready.

**Why:** a release that never becomes ready then costs nothing in capacity. The rollout simply stalls. The trade-off is that rollouts need spare cluster capacity for one extra pod.

## 3. Kustomize over Helm

**Decision:** plain manifests with a base and overlays.

**Why:** two environments with small differences don't need a templating language. Kustomize output is the literal YAML that gets applied, which makes reviews, kubeconform and Checkov straightforward. Helm would be the better fit for distributing the chart to other teams.

## 4. Generated ConfigMap with a content hash

**Decision:** `configMapGenerator`, so the ConfigMap name changes when its content changes.

**Why:** pods only read environment variables at start. A hash-suffixed name changes the pod template, so a config change triggers a normal, observable, reversible rollout instead of silently doing nothing.

## 5. Route templates as metric labels

**Decision:** label by `/api/v1/work`, never `/api/v1/work?ms=5` or `/items/123`; unmatched paths become `unmatched`.

**Why:** raw paths make label cardinality unbounded. A scanner hitting random URLs could otherwise exhaust Prometheus memory.

## 6. Readiness metric computed at scrape time

**Decision:** `app_ready` is a callback evaluated on every scrape, not a value set by `/readyz`.

**Why:** found by running the stack. The first version only updated when something called `/readyz`. Under Kubernetes the probes hid that; anywhere else it falsely reported "not ready" and would have fired an alert.

## 7. Pre-created identities in Terraform

**Decision:** user-assigned control-plane, kubelet and workload identities are created, and granted roles, before the AKS cluster.

**Why:** with system-assigned identities, permissions can only be granted after the cluster exists, which creates ordering races and makes plans depend on unknown computed blocks. The first design hit exactly that in `terraform test`. Pre-created identities also give each workload its own least-privilege identity via federation, instead of every pod sharing the Key Vault add-on identity.

## 8. Authorised IP ranges instead of a private cluster

**Decision:** public API server endpoint restricted by CIDR; Key Vault firewalled, reachable from the AKS subnet via a service endpoint.

**Why:** private clusters and private endpoints need private DNS and self-hosted CI runners, which this project doesn't have. The trade-off is recorded next to the code as Checkov suppressions with reasons.

## 9. Mocked-provider Terraform tests

**Decision:** `terraform test` with `mock_provider`; nothing is applied to Azure.

**Why:** proves naming, wiring, secure settings and guardrail rejections on every PR, with no credentials or cost. The limitation is explicit: it cannot prove Azure accepts every combination.

## 10. Testing reliability on a real cluster in CI

**Decision:** a kind cluster in CI runs rollout, rollback, readiness and self-healing scenarios against the real manifests and image.

**Why:** manifest linting cannot show that a rollout drops zero requests or that `maxUnavailable: 0` keeps capacity during a bad release. Only running it can. The load generator reuses the app image, so the test needs no extra public images.
