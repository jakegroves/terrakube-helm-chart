# Terrakube alert & recording rules

`*.rules.yaml` are **CRD-neutral rule groups** — the exact shape that goes into a
Prometheus `rule_files:` include and into `spec.groups` of either operator CRD.
They are the maintained copy; the `vmrules-*.yaml` wrappers are generated.

| File | Contents |
|---|---|
| `terrakube-slo.rules.yaml` | SLO burn-rate recording rules + alerts (API availability 99.5%, job success 99%) |
| `terrakube-symptoms.rules.yaml` | symptom alerts (DB pool saturation, webhook backlog, executor OOM, service down, collector export, PVC near full) |
| `terrakube-usage.rules.yaml` | recording rules for the activity dashboards + 3 opt-in alerts (ship inert via `and vector(0)`) |

## Consume

**VictoriaMetrics operator** — apply the generated wrappers:

```bash
kubectl apply -f rules/vmrules-slo.yaml -f rules/vmrules-symptoms.yaml -f rules/vmrules-usage.yaml
```

Regenerate them after editing a body:

```bash
bash rules/generate-vmrules.sh
```

**Prometheus operator** — wrap each body in a `PrometheusRule`:

```bash
for s in slo symptoms usage; do
  yq -P '{"apiVersion":"monitoring.coreos.com/v1","kind":"PrometheusRule",
          "metadata":{"name":"terrakube-'"$s"'","labels":{"release":"kube-prometheus-stack"}},
          "spec":{"groups":.groups}}' "rules/terrakube-$s.rules.yaml" \
    > "prometheusrule-$s.yaml"
done
```

(set the `release` label to match your `kube-prometheus-stack` ruleSelector)

**Vanilla Prometheus** — copy the `*.rules.yaml` files where `rule_files:` globs,
or paste each `groups:` list into your rules config.

## Opt-in alerts

Every alert in `terrakube-usage.rules.yaml` ends with `and vector(0)` so it never
fires. To enable one: delete that clause and wire a notifier. Rationale and
thresholds are in `SLO.md` §4; the burn-rate math for the SLO alerts is in the
comments of `terrakube-slo.rules.yaml`.
