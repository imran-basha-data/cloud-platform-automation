#!/usr/bin/env bash
# End-to-end reliability test against a real Kubernetes cluster (kind in CI,
# any cluster locally). Exits non-zero on the first failed expectation.
#
# Scenarios:
#   1. Deploy v1 and wait for readiness; smoke-test through the Service.
#   2. Rolling update v1 -> v2 under continuous traffic: zero failed requests.
#   3. Bad release (readiness never passes): rollout is detected as failed,
#      v2 keeps serving the whole time, `rollout undo` restores it.
#   4. Readiness removes a pod from the Service endpoints (maintenance mode).
#   5. Self-healing: a deleted pod is replaced and the Deployment recovers.
#
# Required environment:
#   IMAGE_V1, IMAGE_V2   images already built (e.g. platform-api:1.0.0 / 1.1.0)
#   LOAD_IMAGE           command that makes a local image available to the
#                        cluster, called as: $LOAD_IMAGE <image>
#                        e.g. "kind load docker-image" or a k3s import script
set -euo pipefail

NAMESPACE="${NAMESPACE:-platform-dev}"
OVERLAY="${OVERLAY:-k8s/overlays/dev}"
DEPLOY="deployment/platform-api"
SERVICE_URL="http://platform-api.${NAMESPACE}.svc.cluster.local"
: "${IMAGE_V1:?set IMAGE_V1}" "${IMAGE_V2:?set IMAGE_V2}" "${LOAD_IMAGE:?set LOAD_IMAGE}"

step() { printf '\n==> %s\n' "$*"; }
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; kubectl -n "$NAMESPACE" get pods -o wide >&2 || true; exit 1; }

# Run Python inside the cluster using the app image itself, so no extra
# client image has to be pulled from a public registry.
in_cluster() {
  local name="$1" script="$2"
  kubectl -n "$NAMESPACE" delete pod "$name" --ignore-not-found --wait=true >/dev/null
  kubectl -n "$NAMESPACE" run "$name" --image="$IMAGE_V1" --restart=Never \
    --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"'"$name"'","image":"'"$IMAGE_V1"'","command":["python","-c"],"args":['"$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$script")"'],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
    >/dev/null
}

wait_pod_done() {
  local name="$1" timeout="${2:-180}"
  kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$name" \
    --timeout="${timeout}s" >/dev/null || {
      kubectl -n "$NAMESPACE" logs "$name" >&2 || true
      fail "pod $name did not complete successfully"
    }
}

ready_endpoints() {
  kubectl -n "$NAMESPACE" get endpointslices -l kubernetes.io/service-name=platform-api \
    -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -c '^true$' || true
}

served_version() {
  in_cluster probe "import json,urllib.request; print(json.load(urllib.request.urlopen('${SERVICE_URL}/api/v1/info', timeout=5))['version'])"
  wait_pod_done probe 60
  kubectl -n "$NAMESPACE" logs probe
}

step "Load images into the cluster"
$LOAD_IMAGE "$IMAGE_V1"
$LOAD_IMAGE "$IMAGE_V2"

step "1. Deploy v1 ($IMAGE_V1)"
kubectl apply -k "$OVERLAY" >/dev/null
kubectl -n "$NAMESPACE" create secret generic platform-api-secrets \
  --from-literal=admin-token="$(python3 -c 'import secrets; print(secrets.token_hex(24))')" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NAMESPACE" set image "$DEPLOY" api="$IMAGE_V1" >/dev/null
kubectl -n "$NAMESPACE" rollout status "$DEPLOY" --timeout=180s
[ "$(served_version)" = "${IMAGE_V1##*:}" ] || fail "service is not serving ${IMAGE_V1##*:}"
pass "v1 deployed and serving through the Service"

step "2. Rolling update to v2 under continuous traffic"
in_cluster loadgen "
import json, time, urllib.request
ok = failed = 0; versions = {}
end = time.time() + 45
while time.time() < end:
    try:
        body = json.load(urllib.request.urlopen('${SERVICE_URL}/api/v1/info', timeout=2))
        ok += 1; versions[body['version']] = versions.get(body['version'], 0) + 1
    except Exception as exc:
        failed += 1; print('error:', type(exc).__name__, exc, flush=True)
    time.sleep(0.05)
print(json.dumps({'ok': ok, 'failed': failed, 'versions': versions}))
"
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/loadgen --timeout=60s >/dev/null
sleep 3
kubectl -n "$NAMESPACE" set image "$DEPLOY" api="$IMAGE_V2" >/dev/null
kubectl -n "$NAMESPACE" rollout status "$DEPLOY" --timeout=180s
wait_pod_done loadgen 120
result="$(kubectl -n "$NAMESPACE" logs loadgen | tail -n 1)"
echo "traffic during rollout: $result"
python3 - "$result" "${IMAGE_V1##*:}" "${IMAGE_V2##*:}" <<'PY' || fail "requests failed during the rolling update"
import json, sys
r = json.loads(sys.argv[1]); v1, v2 = sys.argv[2], sys.argv[3]
assert r["failed"] == 0, r
assert r["ok"] > 100, r
assert v1 in r["versions"] and v2 in r["versions"], r
PY
pass "rolling update completed with 0 failed requests"

step "3. Bad release is detected and rolled back"
kubectl -n "$NAMESPACE" set env "$DEPLOY" APP_FAIL_READINESS=true >/dev/null
if kubectl -n "$NAMESPACE" rollout status "$DEPLOY" --timeout=40s; then
  fail "a release that never becomes ready was reported as successful"
fi
available="$(kubectl -n "$NAMESPACE" get "$DEPLOY" -o jsonpath='{.status.availableReplicas}')"
desired="$(kubectl -n "$NAMESPACE" get "$DEPLOY" -o jsonpath='{.spec.replicas}')"
[ "$available" = "$desired" ] || fail "capacity dropped during bad rollout ($available/$desired)"
[ "$(served_version)" = "${IMAGE_V2##*:}" ] || fail "v2 stopped serving during the bad rollout"
pass "bad rollout stalled with full capacity ($available/$desired) still serving v2"
kubectl -n "$NAMESPACE" rollout undo "$DEPLOY" >/dev/null
kubectl -n "$NAMESPACE" rollout status "$DEPLOY" --timeout=180s
if kubectl -n "$NAMESPACE" get "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].env}' \
  | grep -q APP_FAIL_READINESS; then
  fail "rollback did not remove the bad configuration"
fi
[ "$(served_version)" = "${IMAGE_V2##*:}" ] || fail "rollback is not serving v2"
pass "rollout undo restored v2"

step "4. Readiness controls Service membership"
before="$(ready_endpoints)"
pod_ip="$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component=api \
  -o jsonpath='{.items[0].status.podIP}')"
token="$(kubectl -n "$NAMESPACE" get secret platform-api-secrets -o jsonpath='{.data.admin-token}' \
  | python3 -c 'import base64,sys; print(base64.b64decode(sys.stdin.read()).decode())')"
in_cluster admin "
import urllib.request
req = urllib.request.Request('http://${pod_ip}:8080/api/v1/admin/maintenance', data=b'{\"enabled\": true}',
    headers={'Authorization': 'Bearer ${token}', 'Content-Type': 'application/json'}, method='POST')
print(urllib.request.urlopen(req, timeout=5).read().decode())
"
wait_pod_done admin 60
for _ in $(seq 1 20); do
  after="$(ready_endpoints)"; [ "$after" -lt "$before" ] && break; sleep 2
done
[ "$after" -eq $((before - 1)) ] || fail "pod in maintenance mode still receives traffic ($before -> $after)"
live="$(kubectl -n "$NAMESPACE" get pods -o jsonpath="{.items[?(@.status.podIP=='${pod_ip}')].status.containerStatuses[0].restartCount}")"
[ "$live" = "0" ] || fail "maintenance mode caused a restart"
pass "ready endpoints went $before -> $after without restarting the pod"

step "5. Self-healing after pod deletion"
victim="$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component=api -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "$NAMESPACE" delete pod "$victim" --wait=false >/dev/null
kubectl -n "$NAMESPACE" rollout status "$DEPLOY" --timeout=120s
for _ in $(seq 1 30); do
  ready="$(kubectl -n "$NAMESPACE" get "$DEPLOY" -o jsonpath='{.status.readyReplicas}')"
  pods="$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component=api --no-headers | grep -c Running || true)"
  [ "${ready:-0}" -ge 1 ] && [ "$pods" -ge "$desired" ] && break; sleep 2
done
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component=api --no-headers | grep -q "$victim" \
  && fail "deleted pod $victim still present"
pass "deleted pod replaced; $pods api pods running"

step "All Kubernetes reliability scenarios passed"
kubectl -n "$NAMESPACE" delete pod loadgen probe admin --ignore-not-found >/dev/null
kubectl -n "$NAMESPACE" rollout history "$DEPLOY"
