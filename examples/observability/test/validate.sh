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

echo "== business dashboards present with a datasource variable =="
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

echo "== business rules present =="
yq '.spec.groups[].name' rules/vmrules-business.yaml | grep -q 'terrakube-business.rules' \
  || { echo "missing business recording rules" >&2; exit 1; }
echo "  ok"

echo "== datasources ConfigMap is valid yaml =="
yq . grafana/datasources.yaml >/dev/null && echo "  ok"

echo "ALL OK"
