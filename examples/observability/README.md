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
| `grafana/` | datasources ConfigMap + dashboards (`dashboards/` cross-signal, `dashboards-generic/` metrics), each kustomize-wrapped into sidecar ConfigMaps; `kubectl apply -k grafana/` |
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

The reference stack does **not** bundle Grafana (`grafana.enabled: false` in
`values/victoria-metrics-k8s-stack.values.yaml`) — bring your own and provision
via its sidecar:

1. **Sidecar (recommended)** — a Grafana running the standard dashboard/datasource
   sidecar (both `victoria-metrics-k8s-stack` and `kube-prometheus-stack` ship one).

   Full bundle (this stack's own Grafana, in `observability`):
   ```bash
   kubectl apply -k examples/observability/grafana/
   ```
   Datasources land from the `grafana_datasource: "1"` ConfigMap; the 12
   dashboards from `grafana_dashboard: "1"` ConfigMaps.

   **Already running `kube-prometheus-stack`?** You only want the 7 metric
   dashboards against your existing Prometheus — not the VictoriaMetrics / Tempo /
   VictoriaLogs datasources:
   ```bash
   kubectl apply -k examples/observability/grafana/dashboards-generic/ -n monitoring
   ```
   (use the namespace your Grafana runs in). Then check its sidecar:
   - `sidecar.dashboards.searchNamespace` must include that namespace (it defaults
     to the release namespace only; set it to `ALL` or add the namespace);
   - the sidecar label defaults to `grafana_dashboard` — matches; no `labelValue`
     is set, so `"1"` is fine;
   - the "Terrakube Infrastructure" / "Terrakube Platform" folders only appear if
     `sidecar.dashboards.folderAnnotation: grafana_folder` **and**
     `sidecar.dashboards.provider.foldersFromFilesStructure: true` are set;
     otherwise every dashboard lands in the default folder (harmless);
   - the dashboards bind `${DS_PROMETHEUS}` to the default Prometheus datasource -
     kube-prometheus-stack sets one, so they work out of the box; otherwise pick
     the datasource from the "Metrics source" dropdown.
2. **grafana-operator** — point a `GrafanaDashboard` `spec.configMapRef` at each
   generated `tk-dash-*` ConfigMap.
3. **Terraform** — `for_each` the `grafana_dashboard` provider over
   `grafana/dashboards*/*.json`.
4. **Manual** — Dashboards → Import → paste the JSON.

Adding a dashboard: drop the JSON in `dashboards/` (cross-signal) or
`dashboards-generic/` (metrics), add a `configMapGenerator` entry in that
directory's `kustomization.yaml`, and re-run `test/validate.sh`.

Alternatively, set `grafana.enabled: true` in
`values/victoria-metrics-k8s-stack.values.yaml` for a self-contained demo Grafana
that picks up both ConfigMap sets automatically.

## Swapping the trace backend

Tempo is the default (S3-backed, proven HA). To move to **VictoriaTraces**:
replace `applications/tempo.yaml` with the VictoriaTraces chart, repoint the
gateway collector's `otlp/tempo` exporter in
`values/otel-kube-stack.values.yaml`, and change the Tempo datasource URL in
`grafana/datasources.yaml`. Nothing in the Terrakube app or the `terrakube`
chart changes.

See `COMPONENTS.md` for pinned versions and the resource footprint.
