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

echo "== legacy jaeger fixture assertions =="
OUT=$(helm template tk "$CHART" -f ci/legacy-jaeger-values.yaml)
grep -q 'OTEL_TRACES_EXPORTER: "jaeger"' <<<"$OUT"

echo "ALL OK"
