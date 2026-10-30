# Grafana Dashboard Packaging Reference

## Dashboard Files and Identity

Store each dashboard as `dashboards/<uid>.json`, with the filename matching the dashboard UID for new
dashboards. Preserve established UIDs during migrations. If an existing ConfigMap name or data key
is part of the upgrade contract, encode that compatibility mapping explicitly rather than silently
renaming it.

One template can iterate over `dashboards/*.json` and emit one ConfigMap per file. Each ConfigMap
needs the sidecar discovery label and, when folders are used, the configured folder annotation.
Treat folder-sidecar behavior as cluster-wide and verify how dashboards without annotations are
routed before changing it.

Gate dashboard rendering with an explicit value. Apply the same condition to an umbrella dependency.
Only one release per environment should emit a given dashboard UID.

## Safe Substitution

Never process dashboard JSON or alert rules with Helm `tpl`. Grafana legend tokens such as
`{{instance}}` and Prometheus alert tokens such as `{{ $labels.instance }}` share Helm's delimiters
and can fail parsing or be corrupted.

Use exact replacement of a small, approved placeholder set:

```gotemplate
{{- $json := .Files.Get $path }}
{{- $json = $json | replace "{{ .Values.datasources.prometheus }}" $.Values.datasources.prometheus }}
```

Keep replacements explicit and minimal. Pass every other token through literally. If many fields
need templating, reconsider the input format instead of expanding whole-document evaluation.

## ConfigMap Pattern

Adapt labels, annotations, names, and values paths to the consuming repository:

```gotemplate
{{- if .Values.enabled }}
{{- range $path, $_ := .Files.Glob "dashboards/*.json" }}
{{- $name := trimSuffix ".json" (base $path) }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-{{ $name }}
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: {{ $.Values.dashboardFolder | quote }}
data:
  {{ $name }}.json: |-
{{ $.Files.Get $path | indent 4 }}
{{- end }}
{{- end }}
```

Do not copy this unchanged when the chart has compatibility names, required common labels, targeted
datasource substitutions, or a different sidecar contract.

## Repository-Specific Content

Keep these details local:

* dashboard inventory, titles, queries, metrics, variables, and panel behavior;
* datasource UIDs, authentication, endpoints, and allowed hosts;
* alert rule groups and routing;
* compatibility names and migration mappings;
* deployment ownership and GitOps topology;
* chart publication and environment rollout automation.

The shared skill owns the packaging method. The chart README remains the consumer authority for what
the packaged dashboards require and provide.
