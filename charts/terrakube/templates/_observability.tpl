{{/*
OTEL agent environment for a service, rendered into its ConfigMap data.
Usage: {{ include "terrakube.otelEnv" (dict "svc" "api" "root" $) | nindent 2 }}
*/}}
{{- define "terrakube.otelEnv" -}}
{{- $svc := .svc -}}
{{- $cfg := index .root.Values $svc -}}
{{- $otel := $cfg.otel -}}
{{- $env := (.root.Values.global.observability).environment | default "" -}}
OTEL_JAVAAGENT_ENABLED: "true"
OTEL_SERVICE_NAME: {{ $otel.serviceName | default (printf "terrakube-%s" $svc) | quote }}
OTEL_RESOURCE_ATTRIBUTES: {{ printf "service.namespace=terrakube%s" (ternary (printf ",deployment.environment=%s" $env) "" (ne $env "")) | quote }}
{{- $proto := $otel.protocol | default "otlp" }}
{{- if eq $proto "otlp" }}
{{- if not $otel.otlp.endpoint }}{{ fail (printf "%s.otel.otlp.endpoint is required when %s.otel.protocol is otlp" $svc $svc) }}{{ end }}
OTEL_EXPORTER_OTLP_ENDPOINT: {{ $otel.otlp.endpoint | quote }}
OTEL_EXPORTER_OTLP_PROTOCOL: {{ $otel.otlp.protocol | default "http/protobuf" | quote }}
OTEL_TRACES_EXPORTER: "otlp"
OTEL_METRICS_EXPORTER: "none"
OTEL_LOGS_EXPORTER: {{ ternary "otlp" "none" $otel.logs.enabled | quote }}
OTEL_INSTRUMENTATION_LOGBACK-APPENDER_ENABLED: {{ $otel.logs.enabled | quote }}
OTEL_INSTRUMENTATION_LOGBACK-MDC_ENABLED: "true"
OTEL_TRACES_SAMPLER: "parentbased_traceidratio"
OTEL_TRACES_SAMPLER_ARG: {{ $otel.traces.samplerArg | default "0.1" | quote }}
{{- else if eq $proto "jaeger" }}
OTEL_TRACES_EXPORTER: "jaeger"
OTEL_EXPORTER_JAEGER_ENDPOINT: {{ required (printf "%s.otel.traces.endpoint is required when protocol is jaeger" $svc) $otel.traces.endpoint | quote }}
OTEL_METRICS_EXPORTER: "none"
{{- else if eq $proto "zipkin" }}
OTEL_TRACES_EXPORTER: "zipkin"
OTEL_EXPORTER_ZIPKIN_ENDPOINT: {{ required (printf "%s.otel.traces.endpoint is required when protocol is zipkin" $svc) $otel.traces.endpoint | quote }}
OTEL_METRICS_EXPORTER: "none"
{{- end }}
{{- end -}}

{{/*
Pod-selector labels a metrics scrape (ServiceMonitor / PodMonitor / VMPodScrape) matches.
Usage: {{ include "terrakube.metricsSelectorLabels" (dict "svc" "api" "root" $) | nindent 6 }}
*/}}
{{- define "terrakube.metricsSelectorLabels" -}}
app.kubernetes.io/component: terrakube-{{ .svc }}
app.kubernetes.io/name: {{ include "terrakube.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}
