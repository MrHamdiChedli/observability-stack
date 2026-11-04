#!/usr/bin/env bash
# Proves the monitoring works end to end: metrics are scraped, dashboards and logs are there,
# and stopping the database really fires the alerts, which then resolve.
# Run it where Docker runs (inside the VM: vagrant ssh -c "cd /vagrant && bash tests/observability-test.sh").
set -euo pipefail
cd "$(dirname "$0")/.."

PROM=http://localhost:9090
AM=http://localhost:9093
GRAFANA=http://localhost:3000
LOKI=http://localhost:3100
APP=http://localhost:8080
GRAFANA_AUTH="admin:$(cat secrets/grafana_admin_password.txt)"
fail() { echo "FAIL: $1"; exit 1; }

# Waits until a command succeeds, checking every 5 seconds.
wait_for() {
  local seconds="$1"; shift
  for _ in $(seq 1 $((seconds / 5))); do
    if "$@" > /dev/null 2>&1; then return 0; fi
    sleep 5
  done
  return 1
}
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
traffic() { for _ in $(seq 1 "$1"); do curl -s -o /dev/null --max-time 3 "$APP/" || true; done; }

targets_up() {
  curl -fsS "$PROM/api/v1/targets" \
    | json "sum(t['health']=='up' for t in d['data']['activeTargets'])" | grep -qx 6
}
requests_counted() {
  curl -fsS "$PROM/api/v1/query" --data-urlencode 'query=sum(http_requests_total{endpoint="/"})' \
    | json "float(d['data']['result'][0]['value'][1]) if d['data']['result'] else 0" \
    | python3 -c "import sys; sys.exit(0 if float(sys.stdin.read()) >= 20 else 1)"
}
app_logs_in_loki() {
  curl -fsS -G "$LOKI/loki/api/v1/query_range" --data-urlencode 'query={service="app"}' --data-urlencode 'limit=5' \
    | json "len(d['data']['result'])" | grep -qv '^0$'
}
alert_firing() {
  curl -fsS "$AM/api/v2/alerts?active=true&silenced=false&inhibited=false" \
    | json "' '.join(a['labels']['alertname'] for a in d)" | grep -qw "$1"
}
alert_gone() { ! alert_firing "$1"; }

echo "1. Prometheus scrapes all 6 targets (2 app replicas, postgres, node, prometheus, alertmanager)"
wait_for 90 targets_up || fail "not all targets are up"

echo "2. App requests are counted"
traffic 30
wait_for 60 requests_counted || fail "http_requests_total did not increase"

echo "3. Grafana has its data sources and the dashboard"
wait_for 60 curl -fsS "$GRAFANA/api/health" || fail "Grafana is not healthy"
curl -fsS -u "$GRAFANA_AUTH" "$GRAFANA/api/datasources/uid/prometheus/health" | grep -q '"status":"OK"' \
  || fail "the Prometheus data source is not working"
curl -fsS -u "$GRAFANA_AUTH" "$GRAFANA/api/dashboards/uid/visit-counter" | grep -q '"title":"Visit counter"' \
  || fail "the dashboard is not provisioned"

echo "4. Container logs reach Loki"
wait_for 90 app_logs_in_loki || fail "no app logs in Loki"

echo "5. No alert is firing while everything is healthy"
alert_gone DatabaseDown || fail "DatabaseDown fires on a healthy stack"

echo "6. Stopping the database fires DatabaseDown and HighErrorRate"
docker compose stop db > /dev/null 2>&1
trap 'docker compose start db > /dev/null 2>&1' EXIT
( for _ in $(seq 1 60); do traffic 5; sleep 1; done ) &
load=$!
wait_for 120 alert_firing DatabaseDown || fail "DatabaseDown did not fire"
wait_for 120 alert_firing HighErrorRate || fail "HighErrorRate did not fire"
kill "$load" 2> /dev/null || true

echo "7. Restarting the database resolves DatabaseDown"
docker compose start db > /dev/null 2>&1
trap - EXIT
wait_for 120 alert_gone DatabaseDown || fail "DatabaseDown did not resolve"

echo "PASS: all checks succeeded"
