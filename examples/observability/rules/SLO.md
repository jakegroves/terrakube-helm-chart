# Terrakube SLOs

Three SLOs, each measured over a rolling 30-day window. Alerts are multi-window
multi-burn-rate (Google SRE workbook style) so a fast burn pages immediately and
a slow burn warns before the budget is gone.

## 1. API availability — 99.5%

| | |
|---|---|
| Good events | `http_server_requests_seconds_count{service="terrakube-api", status!~"5.."}` |
| Total events | `http_server_requests_seconds_count{service="terrakube-api"}` |
| Objective | 99.5% success → error budget **0.5%** |
| Recording rules | `terrakube:api_request_error_ratio_rate{5m,30m,1h,6h}` |

**Burn-rate alerts**

| Alert | Condition | Meaning |
|---|---|---|
| `TerrakubeApiAvailabilityFastBurn` | 5m ratio > 14.4×0.5% **and** 1h ratio > 14.4×0.5%, for 2m | Budget gone in ~2 days at this rate — page now |
| `TerrakubeApiAvailabilitySlowBurn` | 30m ratio > 6×0.5% **and** 6h ratio > 6×0.5%, for 15m | Sustained elevated errors — investigate today |

## 2. API latency — p95 < 500 ms

| | |
|---|---|
| Indicator | `histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{service="terrakube-api"}[5m])))` |
| Objective | p95 under 500 ms for 99% of 5-minute windows in the 30d period |

Tracked on the **Terrakube - API** dashboard; add a dedicated burn-rate alert
per-route once the traffic shape is understood (route cardinality makes a single
global p95 noisy).

## 3. Job success — 99%

| | |
|---|---|
| Good events | `terrakube_job_transitions_total{to=~"completed\|noChanges"}` |
| Total events | `terrakube_job_transitions_total{to=~"failed\|completed\|noChanges"}` |
| Objective | 99% → error budget **1%** |
| Recording rule | `terrakube:job_failure_ratio_rate1h` |

**Burn-rate alert**

| Alert | Condition | Meaning |
|---|---|---|
| `TerrakubeJobSuccessSlowBurn` | 1h failure ratio > 6×1%, for 30m | Job failures are consuming the budget |

`cancelled` / `rejected` / `waitingApproval` transitions are excluded — they are
user actions, not reliability failures.

---

## 4. Business rules (`vmrules-business.yaml`)

Not SLOs — supporting recording rules for the three business dashboards
(`terrakube-runs`, `terrakube-flow`, `terrakube-resources-registry`) plus three
alerts that ship **inert**.

**Recording rules**

| Rule | Feeds |
|---|---|
| `terrakube:run_success_rate:ratio_rate1h` / `:ratio_rate6h` | success-rate SLI panels |
| `terrakube:run_success_rate:ratio_rate1h:by_org` | per-org failure tables |
| `terrakube:runs:rate1d` | throughput stat |
| `terrakube:run_duration_seconds:p95_rate1h` | duration stat |
| `terrakube:approval_wait_seconds:p95_rate1h` | approval-wait stat |
| `terrakube:resource_changes:rate1d` | resource-change trends |

**Opt-in alerts** — each expression ends with `and vector(0)`, so it never
fires. To enable: delete that clause and configure a VMAlert notifier.

| Alert | Condition (once enabled) |
|---|---|
| `TerrakubeRunFailureRateHigh` | 1h success rate < 0.8, for 30m |
| `TerrakubeApprovalQueueBacklog` | > 10 runs awaiting approval, for 1h |
| `TerrakubeQueueWaitSLOBreach` | p95 job queue wait > 300s, for 15m |
