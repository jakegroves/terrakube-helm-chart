#!/usr/bin/env bash
# Golden-ish render checks for the observability instrumentation. No unit-test
# framework in this repo - `helm template` output comparison is the test.
set -euo pipefail
cd "$(dirname "$0")/.."

CHART=charts/terrakube

echo "== helm lint =="
helm lint "$CHART"

for f in ci/*-values.yaml; do
  echo "== helm template -f $f =="
  helm template tk "$CHART" -f "$f" >/dev/null
done

echo "== defaults must emit no observability objects =="
if helm template tk "$CHART" | grep -Ei 'OTEL_|kind: ServiceMonitor|kind: PodMonitor|kind: VMPodScrape|prometheus.io/scrape'; then
  echo "LEAK: observability output present with default values" >&2
  exit 1
fi
echo "clean"

echo "== otlp fixture assertions =="
OUT=$(helm template tk "$CHART" -f ci/otlp-values.yaml)
grep -q 'OTEL_EXPORTER_OTLP_ENDPOINT' <<<"$OUT"
grep -q 'OTEL_METRICS_EXPORTER: "none"' <<<"$OUT"
grep -q 'OTEL_LOGS_EXPORTER: "otlp"' <<<"$OUT"
test "$(grep -c 'kind: VMPodScrape' <<<"$OUT")" = "3"
! grep -q '9464' <<<"$OUT"
! grep -qi 'jaeger' <<<"$OUT"

echo "== servicemonitor fixture assertions =="
OUT=$(helm template tk "$CHART" -f ci/servicemonitor-values.yaml)
test "$(grep -c 'kind: ServiceMonitor' <<<"$OUT")" = "3"
grep -q 'release: kube-prometheus-stack' <<<"$OUT"
test "$(grep -c 'honorLabels: true' <<<"$OUT")" = "3"

echo "== otel env var names are valid identifiers =="
OUT=$(helm template tk "$CHART" -f ci/otlp-values.yaml)
grep -q 'OTEL_INSTRUMENTATION_LOGBACK_APPENDER_ENABLED' <<<"$OUT"
grep -q 'OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED' <<<"$OUT"
! grep -q 'LOGBACK-' <<<"$OUT"

echo "== jaeger fixture disables the otlp log exporter =="
grep -q 'OTEL_LOGS_EXPORTER: "none"' <<<"$(helm template tk "$CHART" -f ci/legacy-jaeger-values.yaml)"

echo "== legacy jaeger fixture assertions =="
OUT=$(helm template tk "$CHART" -f ci/legacy-jaeger-values.yaml)
grep -q 'OTEL_TRACES_EXPORTER: "jaeger"' <<<"$OUT"

echo "== example values render =="
helm template tk "$CHART" -f examples/observability-values.yaml >/dev/null

echo "== run/flow/resource observability assets present =="
test -f examples/observability/rules/vmrules-usage.yaml
for d in terrakube-runs terrakube-flow terrakube-resources-registry; do
  test -f "examples/observability/grafana/dashboards-generic/$d.json"
  python3 -m json.tool "examples/observability/grafana/dashboards-generic/$d.json" >/dev/null
done
echo "ok"

echo "== traces / logs dashboards present =="
for d in terrakube-logs traces ui-rum platform-health terrakube-observability-cost; do
  test -f "examples/observability/grafana/dashboards/$d.json"
  python3 -m json.tool "examples/observability/grafana/dashboards/$d.json" >/dev/null
done
grep -q 'metrics_generator\|metricsGenerator' examples/observability/values/tempo-distributed.values.yaml
echo "ok"

echo "== README OTEL section matches the 5.0.0 schema =="
if grep -nE 'zupkin|type: (jaeger|zipkin)' README.md; then
  echo "LEAK: README still documents the pre-5.0.0 otel schema" >&2
  exit 1
fi
grep -qE 'otel\.otlp\.endpoint|otlp:' README.md || { echo "README missing the otlp example" >&2; exit 1; }
echo "clean"

echo "ALL OK"
