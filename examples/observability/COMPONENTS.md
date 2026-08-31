# Reference platform components

Resolved at authoring time (2026-08-28). Bump the `targetRevision` in the
matching `applications/*.yaml` and re-run `test/validate.sh` when upgrading.

| Component | Chart | Version | Upstream | Role |
|---|---|---|---|---|
| OTel Operator + collectors | `open-telemetry/opentelemetry-kube-stack` | `0.20.5` | https://github.com/open-telemetry/opentelemetry-helm-charts | DaemonSet + gateway collectors, `Instrumentation` CR |
| Metrics | `vm/victoria-metrics-k8s-stack` | `0.91.2` | https://github.com/VictoriaMetrics/helm-charts | VM Operator, VMCluster (HA, 30d), VMAgent, VMAlert, Alertmanager, kube-state-metrics, node-exporter |
| Traces | `grafana/tempo-distributed` | `1.61.3` | https://github.com/grafana/helm-charts | S3-backed trace store; metrics-generator (span-metrics + service-graphs) enabled, remote-writes to the VMCluster |
| Logs | `vm/victoria-logs-single` | `0.13.9` | https://github.com/VictoriaMetrics/helm-charts | OTLP log store, 30d |
| Grafana `victoriametrics-logs-datasource` plugin | — | — | https://github.com/VictoriaMetrics/victorialogs-datasource | queried by `terrakube-logs.json` and the log `derivedFields` |
| Dashboards / alerts | (this repo) | — | `grafana/`, `rules/` | 7 metric dashboards (`dashboards-generic/`) + Cost & Scale / Traces / Logs / UI RUM / Platform Health (`dashboards/`) = 12, plus SLO + symptom + usage VMRules |

## Approximate footprint (prod overlay)

| Workload | Replicas | Requests (each) |
|---|---|---|
| vmstorage | 2 | 2 CPU / 4Gi + 200Gi gp3 |
| vmselect / vminsert | 2 / 2 | 1 CPU / 1Gi |
| otel gateway | 2 | ~0.5 CPU / 512Mi |
| otel daemon | per node | ~0.2 CPU / 256Mi |
| tempo (ingester/querier/…) | 3 / 2 / 2 / 2 | ~0.5 CPU / 1Gi |
| victoria-logs | 1 | 1 CPU / 2Gi + 50Gi gp3 |

Dev overlay swaps VMCluster for a single `VMSingle` (7d) and drops most replicas.
