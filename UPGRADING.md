# Upgrading

## 4.x → 5.0.0 — observability / OpenTelemetry

The `otel` values block is now vendor-neutral (OTLP by default) and metrics
scraping is opt-in through one of four mechanisms. This is a **breaking** change
to `values.yaml`.

### Value key changes

| 4.x | 5.0.0 |
|-----|-------|
| `<svc>.otel.metrics.port` / `.host` | **removed.** Metrics are scraped from `/actuator/prometheus` on the existing `http` port. Enable exactly one of `<svc>.metrics.serviceMonitor.enabled`, `<svc>.metrics.podMonitor.enabled`, `<svc>.metrics.vmPodScrape.enabled`, `<svc>.metrics.annotations.enabled`. |
| `<svc>.otel.traces.type: jaeger` | `<svc>.otel.protocol: jaeger` + `<svc>.otel.traces.endpoint` *(deprecated, removed in 6.0.0)* |
| `<svc>.otel.traces.type: zipkin` | `<svc>.otel.protocol: zipkin` + `<svc>.otel.traces.endpoint` *(deprecated)* |
| *(new)* | `<svc>.otel.protocol: otlp` **(default)** + `<svc>.otel.otlp.endpoint` (required when `otel.enabled` and protocol is `otlp`) |
| *(new)* | `global.observability.environment` → `deployment.environment` resource attribute |
| *(new)* | `<svc>.otel.logs.enabled` (default `true`) — ship logs via the agent's OTLP log appender |

### Behaviour changes

- The agent no longer exposes a Prometheus endpoint on port `9464`; that
  containerPort and the `otel-metrics` Service port on the registry are gone.
  `OTEL_METRICS_EXPORTER` is always `none` — metrics come from the Micrometer
  `/actuator/prometheus` endpoint (requires the app image built from Terrakube
  with the matching change).
- `OTEL_SERVICE_NAME` is now lower-case: `TERRAKUBE-API` → `terrakube-api`
  (and `-executor` / `-registry`). Existing trace-backend service lists will
  show the new names alongside the old ones after the upgrade.
- **Application logs are now ECS-JSON on stdout by default** (app change, not a
  chart value): `api` / `executor` / `registry` emit one JSON object per line
  instead of plain text, so a log collector can parse fields and correlate by
  `trace_id`. If you parse container logs as plain text, either update your
  pipeline or add `{ name: LOGGING_STRUCTURED_FORMAT_CONSOLE, value: "" }` to
  `<svc>.env` on each deployment to revert. The bundled `docker-compose` `local`
  profile already keeps human-readable output.
- Every application metric now carries a `service` tag (`terrakube-api` /
  `-executor` / `-registry`). Scrape endpoints are rendered with
  `honorLabels: true` so this tag is preserved; the shipped dashboards and alert
  rules select on it.

### Example

```yaml
global:
  observability:
    environment: prod
api:
  otel:
    enabled: true
    otlp:
      endpoint: http://otel-gateway-collector.observability.svc:4318
  metrics:
    vmPodScrape:
      enabled: true
```

See `examples/observability-values.yaml` for all three services, and
`examples/observability/` for a full self-hosted backend.
