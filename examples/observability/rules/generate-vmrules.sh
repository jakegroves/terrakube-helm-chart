#!/usr/bin/env bash
# Regenerate the VMRule wrappers from the CRD-neutral *.rules.yaml bodies.
# One source of truth: edit the .rules.yaml files, then run this.
#   bash rules/generate-vmrules.sh          # writes rules/vmrules-*.yaml
#   RULES_OUT=/tmp/x bash rules/generate-vmrules.sh   # writes elsewhere (CI diff)
set -euo pipefail
cd "$(dirname "$0")"
OUT="${RULES_OUT:-.}"

for s in slo symptoms usage; do
  case "$s" in
    usage) meta='{"name":"terrakube-usage","namespace":"observability","labels":{"role":"usage"}}' ;;
    *)     meta='{"name":"terrakube-'"$s"'","namespace":"observability"}' ;;
  esac
  yq -P "{\"apiVersion\":\"operator.victoriametrics.com/v1beta1\",\"kind\":\"VMRule\",\"metadata\":${meta},\"spec\":{\"groups\":.groups}}" \
    "terrakube-${s}.rules.yaml" > "${OUT}/vmrules-${s}.yaml"
done
