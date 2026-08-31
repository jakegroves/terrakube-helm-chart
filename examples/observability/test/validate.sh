#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== kustomize overlays build =="
for env in dev staging prod; do
  kustomize build "argocd/overlays/$env" >/dev/null
  n=$(kustomize build "argocd/overlays/$env" | grep -c 'kind: Application')
  test "$n" = "4" || { echo "expected 4 Applications in $env, got $n" >&2; exit 1; }
  echo "  $env: 4 Applications"
done

echo "== values files are valid yaml =="
for f in values/*.values.yaml; do yq . "$f" >/dev/null && echo "  ok $(basename "$f")"; done

echo "== rules are valid yaml =="
for f in rules/*.yaml; do yq . "$f" >/dev/null && echo "  ok $(basename "$f")"; done

echo "== dashboards are valid json =="
for f in grafana/dashboards*/*.json; do python3 -m json.tool "$f" >/dev/null && echo "  ok $(basename "$f")"; done

echo "== activity dashboards present with a datasource variable =="
for d in terrakube-runs terrakube-flow terrakube-resources-registry; do
  f="grafana/dashboards-generic/$d.json"
  test -f "$f" || { echo "missing $f" >&2; exit 1; }
  python3 - "$f" "$d" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
d = json.load(open(path))
vars = [v["name"] for v in d["templating"]["list"]]
assert "DS_PROMETHEUS" in vars, f"no DS_PROMETHEUS var in {name}"
assert all("${DS_PROMETHEUS}" in json.dumps(p.get("datasource", "")) for p in d["panels"]), f"hard-coded datasource in {name}"
assert all(t.get("expr") for p in d["panels"] for t in p.get("targets", [])), f"empty expr in {name}"
PY
  echo "  ok $d"
done

echo "== rule bodies are CRD-neutral and present =="
for f in rules/terrakube-slo.rules.yaml rules/terrakube-symptoms.rules.yaml rules/terrakube-usage.rules.yaml; do
  test -f "$f" || { echo "missing $f" >&2; exit 1; }
  yq -e '.groups | (tag == "!!seq" and length > 0)' "$f" >/dev/null \
    || { echo "$f has no groups: list" >&2; exit 1; }
  echo "  ok $(basename "$f")"
done
yq -e '[.groups[].name] | any_c(. == "terrakube-usage.rules")' rules/terrakube-usage.rules.yaml >/dev/null \
  || { echo "usage recording rules missing" >&2; exit 1; }

echo "== committed VMRules match the generated output =="
tmp=$(mktemp -d)
RULES_OUT="$tmp" bash rules/generate-vmrules.sh
for f in vmrules-slo.yaml vmrules-symptoms.yaml vmrules-usage.yaml; do
  diff <(yq -P 'sort_keys(..)' "rules/$f") <(yq -P 'sort_keys(..)' "$tmp/$f") \
    || { echo "rules/$f is stale - run rules/generate-vmrules.sh" >&2; exit 1; }
done
rm -rf "$tmp"
echo "  ok"

echo "== traces / logs dashboards present =="
for d in terrakube-logs traces ui-rum platform-health terrakube-observability-cost; do
  f="grafana/dashboards/$d.json"
  test -f "$f" || { echo "missing $f" >&2; exit 1; }
  python3 -m json.tool "$f" >/dev/null
  echo "  ok $d"
done
python3 - <<'PY'
import json
d = json.load(open("grafana/dashboards/terrakube-logs.json"))
qs = [v.get("query") for v in d["templating"]["list"] if v.get("type") == "datasource"]
assert "victoriametrics-logs-datasource" in qs, "logs dashboard has no VictoriaLogs datasource var"
assert all(t.get("expr") for p in d["panels"] for t in p.get("targets", [])), "empty target in terrakube-logs"
PY
echo "  ok terrakube-logs structure"

echo "== grafana kustomizations build =="
for d in grafana/dashboards grafana/dashboards-generic grafana; do
  kustomize build "$d" >/dev/null || { echo "kustomize build $d failed" >&2; exit 1; }
done
built=$(kustomize build grafana)
n_dash=$(yq -N 'select(.kind == "ConfigMap" and .metadata.labels.grafana_dashboard == "1") | .metadata.name' <<<"$built" | grep -c .)
test "$n_dash" -ge 12 || { echo "expected >=12 dashboard ConfigMaps, got $n_dash" >&2; exit 1; }
n_folder=$(yq -N 'select(.kind == "ConfigMap" and .metadata.labels.grafana_dashboard == "1") | .metadata.annotations.grafana_folder' <<<"$built" | grep -c 'Terrakube')
test "$n_folder" = "$n_dash" || { echo "some dashboard ConfigMaps lack a grafana_folder annotation" >&2; exit 1; }
# every source dashboard JSON parses (kustomize build already fails on a missing file)
for f in grafana/dashboards*/*.json; do python3 -m json.tool "$f" >/dev/null; done
echo "  ok $n_dash dashboard ConfigMaps"

echo "== tempo metrics-generator processors enabled =="
grep -Eq 'span-metrics' values/tempo-distributed.values.yaml \
  && grep -Eq 'service-graphs' values/tempo-distributed.values.yaml \
  || { echo "tempo-distributed values missing generator processors" >&2; exit 1; }
echo "  ok"

echo "== datasource cross-links present =="
grep -q 'derivedFields' grafana/datasources.yaml || { echo "no log derivedFields" >&2; exit 1; }
grep -q 'exemplarTraceIdDestinations' grafana/datasources.yaml || { echo "no exemplar destinations" >&2; exit 1; }
grep -q 'tracesToMetrics' grafana/datasources.yaml || { echo "no tracesToMetrics" >&2; exit 1; }
echo "  ok"

echo "== datasources ConfigMap is valid yaml =="
yq . grafana/datasources.yaml >/dev/null && echo "  ok"

echo "ALL OK"
