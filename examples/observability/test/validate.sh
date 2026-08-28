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

echo "== datasources ConfigMap is valid yaml =="
yq . grafana/datasources.yaml >/dev/null && echo "  ok"

echo "ALL OK"
