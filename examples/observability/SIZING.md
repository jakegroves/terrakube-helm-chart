# Sizing the observability stack

How many time series will Terrakube produce, how much disk will that take, and
which knobs trade fidelity for cost. Measure your own numbers with the load
generator in the app repo —
[`terrakube-io/terrakube` → `telemetry-compose/loadgen/`](https://github.com/terrakube-io/terrakube/tree/main/telemetry-compose/loadgen)
— the last section shows how.

`N` = organizations (the `organization` metric label is bounded at
`io.terrakube.metrics.max-organization-tags`, default **200**, over a rolling
2-hour window, so `min(N,200)` below). `R` = distinct span names ≈ HTTP routes +
parameterised SQL shapes. `W` = workspaces. All app meters also carry a fixed
`service` tag (3 values) that does not multiply per-org cardinality.

## 1. Cardinality

| Meter family | Active series ≈ |
|---|---|
| `terrakube_run_finished_total` | `outcome(7) · via(7) · min(N,200)` = `49·min(N,200)` |
| `terrakube_run_started_total` | `via(7) · min(N,200)` = `7·min(N,200)` |
| `terrakube_run_duration_seconds` | `3 (count/sum/max) · outcome(7) · min(N,200)` = `21·min(N,200)` — **`·(buckets+2)` instead of `·3` if you enable `percentiles-histogram`** (see §3) |
| `terrakube_run_approval_wait_seconds` | `3 · min(N,200)` |
| `terrakube_resource_changes_total` | `phase(2) · action(6) · min(N,200)` = `12·min(N,200)` |
| `terrakube_plan_result_total` | `result(3) · min(N,200)` |
| `terrakube_registry_download_total` / `_resolve_seconds` | `type(2) · min(N,200)` (+ `·3` for the resolve timer) |
| `terrakube_registry_modules` / `_providers` | `min(N,200)` each |
| `terrakube_job_queue_wait_seconds` | `3 · min(N,200)` |
| `terrakube_job_transitions_total` | `to(~12)` |
| `terrakube_build_info` | `3` (one per service) |
| `traces_spanmetrics_calls_total` + `_latency_*` | `services(4) · R · status(3) · (le≈17 + 2)` ≈ `230·R` |
| `traces_service_graph_*` | `edges(≈ services²=16) · (le≈8 + 2)` ≈ `160` |
| baseline — `jvm_*`, `process_*`, `system_*`, `hikaricp_*` (api), `logback_events_total`, `executor_*`, `jdbc_*`, `otelcol_*`, `vm_*`, `vl_*`, `tempo_*` | ~8–12k fixed |
| `http_server_requests_seconds_*` | `R · methods(~4) · statuses(~5) · (le≈15 + 2)` ≈ `340·R` (percentile-histogram is **on** for this one) |

### Worked example — `N = 200`, `R ≈ 150`, 10k runs/day

```
run.finished        98·200            = 19 600
run.started         14·200            =  2 800
run.duration        42·200            =  8 400   (≈ 68 000 with percentile-histogram)
resource.changes    12·200            =  2 400
plan.result          3·200            =    600
registry (5 meters)                   ≈  2 000
spanmetrics + graph 230·150 + 160     ≈ 34 700
http_server_requests 340·150          ≈ 51 000
baseline                              ≈ 12 000
-----------------------------------------------
TOTAL                                 ≈ 133 000 active series
```

Dropping the `organization` label (§3) collapses the six `terrakube_*` per-org
families ~200× — to a few hundred series each — for **≈ 55 000** total.

## 2. Storage

VictoriaMetrics stores ≈ **0.5–1.0 B / sample** after compression.

```
133 000 series · (60 / 15 s) samples/min · 1440 min/day · 30 days · 0.8 B
  ≈ 13 GB / 30 days
```

Logs — `L` lines/run (≈ 200 for a plan+apply, mostly INFO) · 10k runs/day ·
~250 B/line compressed:

```
200 · 10 000 · 250 B · 30 days ≈ 15 GB / 30 days   (ERROR-only ≈ 1–2 % of that)
```

Traces — ≈ 40 spans/run · ~400 B/span:

```
40 · 10 000 · 400 B · 30 days ≈ 4.8 GB/day  at 100 % sampling
                              ≈ 15 GB / 30 days  at 10 % sampling
```

## 3. Tuning knobs

| Knob | Where | Effect / tradeoff |
|---|---|---|
| **trace sampling ratio** | local: `OTEL_TRACES_SAMPLER=parentbased_traceidratio` + `OTEL_TRACES_SAMPLER_ARG=0.1` in `.envApi`/`.envExecutor`/`.envRegistry` (or `setupDevelopmentEnvironment.sh`). reference: `values/otel-kube-stack.values.yaml` gateway `tail_sampling.policies[probabilistic].sampling_percentage` | 10× less trace storage + collector CPU. You lose the trace for ~90 % of *non-error, non-slow* requests. The reference gateway **tail-samples**, so it always keeps errors + >1 s traces regardless of the ratio. |
| **drop the `organization` metric label** | a `@Bean MeterFilter` returning `io.micrometer.core.instrument.config.MeterFilter.ignoreTags("organization")` per service, **or** lower `io.terrakube.metrics.max-organization-tags` | `terrakube_run_*` / `resource_changes` / `registry_*` shrink ~`min(N,200)×`. You lose per-org dashboard breakdowns; fleet-level panels are unaffected. |
| **percentile histograms** | `management.metrics.distribution.percentiles-histogram.terrakube.run.duration=true` (adds ~17 `le` buckets per tag combo) | needed for `histogram_quantile()` on `terrakube_run_duration_seconds` / `_approval_wait_seconds` / `_job_queue_wait_seconds`; without it those Timers are count/sum/max only and the Flow-dashboard percentile panels are empty. Costs `(buckets+2)/3 ≈ 6×` the series for those families. |
| **metrics retention** | local: `--retentionPeriod=<Nd>` on the `victoriametrics` service in `telemetry-compose/backend.yml`. reference: `values/victoria-metrics-k8s-stack.values.yaml` VMCluster `retentionPeriod` | linear on disk. |
| **VM downsampling** | `-downsampling.period=30d:5m` (VictoriaMetrics enterprise); or dedup with `-dedup.minScrapeInterval=<scrape interval>` | older data at coarser resolution; dedup is free and safe when a series is scraped by exactly one target. |
| **scrape interval** | `telemetry-compose/backend-scrape.yaml` `global.scrape_interval`; reference VMAgent `scrapeInterval` | 30 s vs 15 s halves sample volume; `rate()` windows must widen to match. |
| **log retention** | local: `--retentionPeriod` on the `victoria-logs` service. reference: `values/victoria-logs-single.values.yaml` `retentionPeriod` | VictoriaLogs (pinned version) has no per-severity retention — shorten globally, or accept 30 d. |
| **span-metrics dimensions** | `tempo.yaml` `metrics_generator.processor.span_metrics.dimensions` (local) / `values/tempo-distributed.values.yaml` (reference) | fewer dimensions = fewer `traces_spanmetrics_*` series. Never add `workspace.id`/`job.id`/`organization.id`. |

## 4. Measure your own numbers

In a checkout of [`terrakube-io/terrakube`](https://github.com/terrakube-io/terrakube),
bring up the from-source loop (`./.devcontainer/dev-fromsource.sh up`), then:

```bash
cd telemetry-compose/loadgen
./loadgen.sh seed --orgs 20 --workspaces 5
./loadgen.sh ramp --steps 1,10,50,100 --hold 10m
# open Grafana -> "Terrakube - Observability Cost & Scale" and read each row at each ramp step
./loadgen.sh teardown
```

Snapshot the drivers:

```
count({__name__=~"terrakube_.*"})                                          # Terrakube cardinality
count({__name__!=""})                                                       # total active series
count(traces_spanmetrics_calls_total)                                       # span-metrics cardinality
sum(rate(vm_rows_inserted_total[5m]))                                       # metrics ingest samples/s
deriv(sum(vm_data_size_bytes)[30m:5m]) * 3600 / 1e6                         # VM disk growth MB/hour
sum(rate(vl_bytes_ingested_total[5m]))                                      # log ingest bytes/s
process_cpu_usage{service="terrakube-api"}                                  # api CPU (0-1 per core)
sum(jvm_memory_used_bytes{service="terrakube-api",area="heap"}) /1024/1024  # api heap MB
sum(jvm_memory_used_bytes{service="terrakube-executor",area="heap"}) /1024/1024
max by (job) (scrape_duration_seconds)                                      # scrape cost
```

(Terrakube's services expose `jvm_*` and `process_cpu_usage`, not `process_resident_memory_bytes`.)

## 5. Captured reference run

**telemetry-compose from-source loop + backend, WSL2 (16 vCPU / 15 GB RAM),
2026-08-29** — one data point on one machine; run §4 for yours.

`loadgen.sh seed --orgs 4 --workspaces 4` then
`run --rate 24/min --duration 6m --mix plan=45,apply=40,reject=10,fail=5`
(≈130 jobs) — measured mid-run, backend on **fresh** stores:

| Metric | value |
|---|---|
| total active series | ~12 300 |
| Terrakube (`terrakube_*`) series | ~66 (4 orgs; grows toward ~130 as the job queue drains) |
| span-metrics (`traces_spanmetrics_*`) series | ~520 |
| metrics ingest | ~700 samples/s |
| VictoriaMetrics disk growth | ~21 MB/hour |
| log ingest | ~78 KB/s |
| api heap | ~800 MB · api CPU <0.01 core (idle — the **executor** is the serial bottleneck) |
| executor heap | ~220 MB |
| max scrape duration | 0.01 s |
| collector export failures | 0 /s |

Notes: a single from-source executor processes jobs serially (~15–20 s each), so
`--rate` above ~4/min just deepens the queue — visible as rising
`terrakube_job_queue_wait_seconds` on the **Flow Efficiency** dashboard, which is
itself a useful thing to demo. For a throughput curve, scale executor replicas
(`executor.replicaCount` in the chart) and re-run.

## 6. Reference-stack metric job names

The Cost & Scale dashboard `sum()`s across components, so it works on both
stacks, but per-job breakdowns differ:

| Signal | telemetry-compose job | `vm-k8s-stack` / operator |
|---|---|---|
| VictoriaMetrics self | (implicit self-scrape) | `vmsingle` / `vminsert` / `vmselect` / `vmstorage` pods |
| VictoriaLogs self | `victoria-logs` | `victoria-logs-single-server` pod |
| Tempo self | `tempo` | `tempo-distributed` `distributor` / `metrics-generator` pods |
| OTel Collector self | `otel-collector` | `otel-gateway-collector` / `otel-daemon-collector` |
