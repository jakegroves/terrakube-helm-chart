# Terrakube reference observability platform

**This is one opinionated stack, not a requirement.** The Terrakube application
and the `terrakube` chart emit vendor-neutral telemetry — OTLP traces/logs and a
Prometheus `/actuator/prometheus` endpoint. If you already run Grafana Cloud,
Datadog, `kube-prometheus-stack`, or anything else, ignore this directory: set
`<svc>.otel.otlp.endpoint` and one of `<svc>.metrics.{serviceMonitor,podMonitor,
vmPodScrape,annotations}.enabled` in your Terrakube values and you're done.

What this directory gives you, if you want a turnkey self-hosted backend:

```
OpenTelemetry Collector (kube-stack)  ─┬─► Tempo            (traces)
                                       │      └─ metrics-generator ─► VictoriaMetrics
                                       │         (span metrics + service graph)
                                       └─► VictoriaLogs     (logs)
VMAgent scrapes /actuator/prometheus  ───► VictoriaMetrics  (metrics, 30d)
                                            │
Grafana ◄───────────────────────────────────┘  + Tempo + VictoriaLogs datasources
VMAlert ──► Alertmanager                         (SLO + symptom rules)
```

Tempo's metrics-generator is enabled in `values/tempo-distributed.values.yaml`
(`metricsGenerator` + `overrides.defaults.metrics_generator.processors:
[service-graphs, span-metrics]`) and remote-writes `traces_spanmetrics_*` /
`traces_service_graph_*` into the VMCluster. The datasources
(`grafana/datasources.yaml`) wire the three signals together: trace→logs
(`tracesToLogsV2`), log→trace (VictoriaLogs `derivedFields`), trace→metrics and
metric→trace exemplars. `grafana/dashboards/` includes `terrakube-logs.json`
(LogsQL) alongside `traces.json` / `ui-rum.json` / `platform-health.json` —
identical to the copies in `telemetry-compose/` so local and cluster look the
same.

## Layout

| Path | What |
|---|---|
| `values/` | committed `values.yaml` per upstream chart |
| `applications/` | one ArgoCD `Application` per chart (multi-source: chart + a `$values` ref back to this repo) |
| `argocd/overlays/{dev,staging,prod}` | kustomize; per-env sizing patch |
| `argocd/root-app.yaml` | app-of-apps — point its `path:` at the overlay for your env |
| `grafana/` | datasources ConfigMap (+ cross-signal links) + dashboards: `dashboards-generic/` (metrics) and `dashboards/` (Traces, Logs, UI RUM, Platform Health) |
| `rules/` | `VMRule` SLO burn-rate + symptom alerts, `SLO.md` |
| `test/validate.sh` | offline checks (kustomize build, yaml/json lint) |
| `SIZING.md` | cardinality/storage formula, tuning knobs, and how to measure your own scale with `telemetry-compose/loadgen/` |

## Prerequisites

- ArgoCD installed, with this repo added as a project source
- An ingress controller (for Grafana / Alertmanager UIs)
- A `gp3` (or equivalent) StorageClass
- For Tempo: an S3 bucket + an IRSA role — fill `REPLACE_TEMPO_BUCKET`,
  `REPLACE_REGION`, `REPLACE_TEMPO_IRSA_ROLE_ARN` in
  `values/tempo-distributed.values.yaml`

## Install

1. Fill every `REPLACE_*` token:
   - `values/otel-kube-stack.values.yaml` → `REPLACE_UI_ORIGIN`
   - `values/victoria-metrics-k8s-stack.values.yaml` → `REPLACE_CLUSTER_NAME`
   - `values/tempo-distributed.values.yaml` → bucket / region / IRSA role
2. Edit `argocd/root-app.yaml` `path:` for your environment (or copy it per env).
3. `kubectl apply -f argocd/root-app.yaml`

## Grafana

Two options, documented in `grafana/`:

- **Existing Grafana (recommended):** apply `grafana/datasources.yaml` (a sidecar
  ConfigMap) and load the dashboard JSON via your usual mechanism.
- **Self-contained demo:** set `grafana.enabled: true` in
  `values/victoria-metrics-k8s-stack.values.yaml`; it picks up the datasources
  ConfigMap and the dashboards automatically.

## Swapping the trace backend

Tempo is the default (S3-backed, proven HA). To move to **VictoriaTraces**:
replace `applications/tempo.yaml` with the VictoriaTraces chart, repoint the
gateway collector's `otlp/tempo` exporter in
`values/otel-kube-stack.values.yaml`, and change the Tempo datasource URL in
`grafana/datasources.yaml`. Nothing in the Terrakube app or the `terrakube`
chart changes.

See `COMPONENTS.md` for pinned versions and the resource footprint.
