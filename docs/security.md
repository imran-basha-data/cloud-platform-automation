# Security

## Controls by layer

| Layer | Controls |
|---|---|
| Application | config validated at startup; prod requires a 16+ character admin token and forbids fault injection; bearer token compared in constant time; admin endpoint disabled (404) without a token; secrets masked in `repr`; OpenAPI docs disabled in prod; errors never leak stack traces to clients |
| Dependencies | runtime dependencies fully pinned (direct and transitive); `pip-audit --strict` in CI; bandit static analysis |
| Container | multi-stage build; no compilers in runtime; uid 10001; works with read-only root FS and all capabilities dropped; `.dockerignore` excludes `.git`, `.env*`, tests and IaC; optional CA bundle passed as a BuildKit secret, never a layer; Trivy blocks fixable HIGH/CRITICAL |
| Kubernetes | restricted Pod Security Standard enforced per namespace; `runAsNonRoot`, `allowPrivilegeEscalation: false`, `drop: [ALL]`, `RuntimeDefault` seccomp, read-only root FS; no service-account token mounted; ingress NetworkPolicy (same namespace + monitoring only); resource limits; Secret values never committed; admin Secret required in prod |
| Azure (Terraform) | AKS local accounts disabled, Entra ID + Azure RBAC only; workload identity; Azure Policy add-on; network policy; encryption at host; authorised API IP ranges (required in prod); identity-based ACR pulls (no admin user, no anonymous pull); Key Vault RBAC, purge protection, default-deny firewall; per-workload identity with a federated credential; Log Analytics ingestion cap |
| Pipeline | `permissions: contents: read`; no repository secrets needed; gitleaks over full history; Checkov over Terraform, rendered manifests and Dockerfile |
| Local tooling | Compose binds every port to 127.0.0.1; Grafana anonymous access is read-only Viewer |

## Accepted risks

Each is suppressed **in code, next to the resource, with its reason**. None is a blanket ignore.

| Finding | Why accepted | What would close it |
|---|---|---|
| AKS not private; Key Vault has a public endpoint | needs private DNS and self-hosted runners | private cluster + private endpoints + self-hosted runners |
| No customer-managed disk keys | needs a Disk Encryption Set and key rotation | DES backed by Key Vault |
| ACR scanning, quarantine, signing, geo-replication | subscription-level, preview, deprecated, or single-region | Defender for Containers; Notation signing |
| Image tags not digests | readability in Git | resolve tags to digests at deploy time |
| Secret as env var, not file | single token read at startup | mount as file and read via `secrets_dir` |
| Free AKS tier in dev | cost | — (prod enforces Standard) |

## Secrets

- Nothing secret is committed. The admin token is created at deploy time (`kubectl create secret`, or from Key Vault in Azure).
- CI uses only ephemeral, generated tokens inside the kind cluster.
- Terraform state can hold sensitive values, so the backend is remote Azure Storage with Entra ID auth (`use_azuread_auth`), and `*.tfstate`, `terraform.tfvars` and `*.backend.hcl` are git-ignored.
