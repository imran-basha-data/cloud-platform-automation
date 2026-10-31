#!/usr/bin/env bash
# Smoke test for the local observability stack (monitoring/docker-compose.yml).
# Asserts that Prometheus scrapes the API and loads every rule, that the
# readiness and error-ratio series are correct, that no alert fires falsely,
# and that Grafana has provisioned the dashboard and can query Prometheus.
set -euo pipefail

PROM="${PROM_URL:-http://localhost:9090}"
GRAFANA="${GRAFANA_URL:-http://localhost:3000}"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

query() {  # prints the first sample value of an instant query, or "none"
  curl -fsS --get "$PROM/api/v1/query" --data-urlencode "query=$1" | python3 -c '
import json, sys
r = json.load(sys.stdin)["data"]["result"]
print(r[0]["value"][1] if r else "none")'
}

echo "waiting for Prometheus and Grafana..."
timeout 120 bash -c "until curl -fs $PROM/-/ready >/dev/null && curl -fs $GRAFANA/api/health >/dev/null; do sleep 2; done" \
  || fail "stack did not become ready"

timeout 60 bash -c "until [ \"\$(curl -fsS --get $PROM/api/v1/query --data-urlencode 'query=up{job=\"platform-api\"}' | grep -c '\"1\"')\" -ge 1 ]; do sleep 2; done" \
  || fail "platform-api target is not up"
pass "Prometheus is scraping platform-api"

rules="$(curl -fsS "$PROM/api/v1/rules" | python3 -c '
import json, sys
groups = json.load(sys.stdin)["data"]["groups"]
rules = [r for g in groups for r in g["rules"]]
bad = [r["name"] for r in rules if r["health"] not in ("ok", "unknown")]
print(len(rules), ",".join(bad) or "-")')"
[ "${rules%% *}" = "9" ] || fail "expected 9 rules, got: $rules"
[ "${rules##* }" = "-" ] || fail "unhealthy rules: ${rules##* }"
pass "9 alerting/recording rules loaded and healthy"

[ "$(query 'app_ready')" = "1" ] || fail "app_ready should be 1 for a healthy instance"
pass "app_ready reports 1 without any probe traffic"

# Spread traffic across several scrapes: rate() needs at least two samples
# that differ, otherwise the ratio is 0/0 = NaN (correct, but not testable).
for _ in $(seq 1 30); do
  curl -fsS -o /dev/null http://localhost:8080/api/v1/info
  curl -sS -o /dev/null http://localhost:8080/does-not-exist || true
  sleep 0.5
done
timeout 90 bash -c "until [ \"\$(curl -fsS --get $PROM/api/v1/query --data-urlencode 'query=job:http_request_errors:ratio_rate5m' | grep -o '\"0\"' | head -1)\" = '\"0\"' ]; do sleep 3; done" \
  || fail "error ratio should settle at 0 (404s are not server errors), got $(query 'job:http_request_errors:ratio_rate5m')"
pass "error ratio is an explicit 0 with no 5xx responses"

firing="$(curl -fsS "$PROM/api/v1/alerts" | python3 -c '
import json, sys
alerts = json.load(sys.stdin)["data"]["alerts"]
print(",".join(a["labels"]["alertname"] for a in alerts if a["labels"]["alertname"] != "PlatformApiHighLatency") or "-")')"
[ "$firing" = "-" ] || fail "unexpected pending/firing alerts: $firing"
pass "no false-positive alerts"

dash="$(curl -fsS "$GRAFANA/api/search?query=Platform%20API" | python3 -c 'import json,sys; print(",".join(d["uid"] for d in json.load(sys.stdin)))')"
[ "$dash" = "platform-api" ] || fail "dashboard not provisioned (got: $dash)"
ready="$(curl -fsS --get "$GRAFANA/api/datasources/proxy/uid/prometheus/api/v1/query" --data-urlencode 'query=sum(app_ready)' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["result"][0]["value"][1])')"
[ "$ready" = "1" ] || fail "Grafana could not query Prometheus"
pass "Grafana dashboard provisioned and datasource working"
