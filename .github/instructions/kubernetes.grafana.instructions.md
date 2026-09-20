---
description: 'Grafana dashboard delivery through GitOps — chart packaging, sidecar provisioning, datasources and secrets, template variables and panel authoring pitfalls.'
applyTo: '**/dashboards/**,**/*dashboard*.json,**/grafana/**'
---

# Grafana

Conventions for authoring Grafana dashboards that are delivered as Kubernetes manifests and query
Prometheus or arbitrary REST/JSON endpoints. Keep application-specific facts — endpoint paths,
secret names, metric names, entity names — in the consuming repository's own instructions, never in
a shared file.

## Packaging Dashboards in a Chart

- Author each dashboard as a plain `<uid>.json` file under a `dashboards/` folder, with the filename
  matching the dashboard `uid`. One chart template iterates `.Files.Glob "dashboards/*.json"` and
  emits one `ConfigMap` per file. Dashboards then stay lintable JSON rather than YAML-embedded text,
  and adding a board is dropping in a file.
- Label every dashboard `ConfigMap` with the sidecar discovery label (`grafana_dashboard: "1"` for
  the kube-prometheus-stack sidecar). Discovery is label-driven; there is no registration step.
- Route dashboards into a named folder with a `grafana_folder: <Folder>` annotation on each
  `ConfigMap`, and set the sidecar to `sidecar.dashboards.folderAnnotation: grafana_folder` plus
  `provider.foldersFromFilesStructure: true`. Without both sidecar settings the annotation is
  ignored and every dashboard lands in the default folder.
- Treat the sidecar configuration as cluster-wide. It is shared by every dashboard-producing
  workload, so enabling folder-from-structure behaviour re-routes existing dashboards that carry no
  annotation into a folder named after their source path. Verify the others still land where
  expected.
- A dashboard `ConfigMap` re-imports on content change with no version bump, unlike a provisioned
  datasource.

## Helm Templating and Dashboard JSON

- Never run dashboard JSON through Helm's `tpl`. Grafana legend and label interpolation tokens such
  as `{{instance}}` or `{{job}}` are valid Grafana syntax but collide with Helm's `{{ }}` action
  delimiters, and `tpl` fails to parse the whole document.
- To inject a small number of values, such as datasource UIDs, use a targeted string `replace` of
  known placeholders rather than `tpl` over the document.
- Only the placeholders explicitly replaced are substituted; anything else is passed through
  literally. Keep such placeholders to the minimum the panels actually consume.
- If templating a dashboard is unavoidable, escape every Grafana token first — but prefer the
  targeted replace, which cannot break on a token added later by a panel editor.

## Datasource Provisioning and Secrets

- Provision datasources from provisioning YAML held in chart values. A provisioned datasource is
  read-only in the UI, so it cannot be repaired through the API.
- For a secured endpoint use HTTP Basic auth and reference an environment variable with
  `$__env{VAR_NAME}`, backed by a `Secret` mounted into the Grafana pod.
- The credential in that `Secret` must match the credential the upstream system actually validates
  against. When the two drift, every panel on the datasource returns 401 and the dashboard looks
  broken for reasons that have nothing to do with the query.
- Grafana reads environment variables at pod start. Changing the `Secret` does nothing until the
  Grafana workload restarts, either manually or through a reloader controller.
- `$__env{}` is expanded at provisioning time. A datasource provisioned while the `Secret` still
  held a placeholder keeps the stale expansion.
- Grafana auto-increments a provisioned datasource's stored `version`. If the `version` in the
  provisioning YAML is less than or equal to the stored value, Grafana skips the update and keeps
  the stale expansion across restarts. Bump the `version` above the stored value, commit and sync.
- A GitOps controller with self-heal enabled reverts a live `kubectl` patch to a `Secret` within
  minutes. Commit the durable fix; treat a live patch as diagnosis only.

## Datasource Base URLs

- When a datasource defines a base URL, every query URL is appended to it. An absolute URL naming a
  different host therefore produces a malformed result such as `http://a.example.com:80http://b.example.com:80/path`,
  and the query fails with a port-parsing error.
- The fix is a second datasource whose base URL is the other host, queried with relative URLs. Adding
  the other host to an allow-list does not help, because the allow-list governs permission, not URL
  composition.
- Give each datasource the credentials the host it points at expects, and keep its allowed hosts
  narrowed to that host.

## Template Variables

- Derive list variables from live metric labels, for example `label_values(app_requests_total,
  service)`, or from a scoped API list. Never populate a dropdown from a full reference catalogue
  returning thousands of rows — it is unusable, and it lists entities with no data on the board.
- Source each board's variable from the metric that board actually plots. A variable shared across
  boards that visualise different signals either lists entities with empty panels or omits entities
  that do have data.
- A counter-derived variable only returns series active inside the dashboard time range, so a narrow
  default range yields an empty dropdown for a low-frequency counter. Give such variables
  `refresh: 2` (on time range change) and a wider default range.
- `includeAll` with an empty `allValue` is not honoured; Grafana sends the joined option list or
  `$__all`, which an equality filter matches to zero rows. Set `allValue: " "` (a single space) and
  have the endpoint treat whitespace as no filter. This applies to any `field=${var}` URL parameter.
- Use a single-value variable wherever the value is interpolated into a path segment or into an
  exact-match server-side filter. Use a multi-value variable only where the consumer is a regex
  matcher that accepts an alternation.
- Chain variables with regex custom variables to add grouping without a new metric label: a
  single-value `custom` variable whose option values are regexes, with `includeAll: true` and
  `allValue: ".*"`, nested into the list variable query as
  `label_values(app_requests_total{service=~"$group"}, service)`. Repeated matchers on the same
  label are ANDed. Defaults leave the board unfiltered, so the feature is purely additive.
- Keep grouping variables single-value. The multi-value `${var:regex}` format escapes the values,
  which breaks options that are themselves regexes.
- A hand-maintained regex group list is a stopgap. A real label on the metric removes the
  maintenance, at the cost of producer-side code.

## Panel Authoring

- Aggregate away `instance` and `pod` labels or every producer redeploy doubles the legend. Wrap
  value queries as `sum by (<keep>)` for counters and rates, `avg by (<keep>)` for gauges, and
  `histogram_quantile(q, sum by (le, <keep>) (rate(<metric>_bucket[5m])))` for histograms. Keep only
  the labels the legend uses.
- Set `color.mode: "palette-classic-by-name"` for stable per-series colours. The default palette
  colours by series order, so a series changes colour between panels and shifts as series come and
  go.
- Prefer the documented time globals `${__from}` and `${__to}` for new panels.
- A timeseries panel needs a genuinely time-typed column, not just a time-oriented output format.
  Declare the column type explicitly on an ISO-8601 field.
- Prefer a backend parser for JSON queries so filtering and caching happen server-side.
- Fix the returned columns explicitly. An empty column list auto-detects every field, which pulls
  large blob columns the panel never uses.
- Table column order follows the returned data frame, not the query column list. Pin it with an
  `organize` transformation, whose `indexByName` maps each column alias to a zero-based position, and
  whose `excludeByName` and `renameByName` hide and retitle columns.
- Table column width is a per-field override (`custom.width`) in `fieldConfig.overrides`, matched
  `byName` or `byRegexp`. Grafana merges multiple overrides on one field, so a column can carry both
  a width and a value mapping.
- Colour a table column by value with a `byName` override setting `custom.cellOptions.type` to
  `color-background` or `color-text`, plus a value mapping carrying a colour per value. Avoid the
  named colour `text` for a background cell — on a dark theme it resolves to near-white and reads as
  blank. Use an explicit neutral grey for unknown states.

## Formatting Scaled and Monetary Values

- Where a numeric value is scaled, or its display precision varies per row, expose a preformatted
  string sibling alongside the raw number, for example `<field>` and `<field>Display`. Render the
  string server-side at the precision that row requires, with thousands grouping and fixed decimals.
- Bind table columns to the preformatted string. A per-field `decimals` or `unit` setting is static
  and cannot vary precision per row, so a mixed-precision table only renders correctly from a
  per-row server-formatted string.
- Keep the raw numeric field as well, for correct numeric sorting and any client-side arithmetic.
  Sort on the number, display the string.
- Timeseries, stat and gauge panels must use the raw numeric — a formatted string cannot be plotted.
  Format those through the panel's `unit` and `decimals`. The preformatted-string rule applies to
  table columns only.

## API Responses Consumed by Dashboards

- An endpoint feeding a dashboard must return lean, acyclic JSON.
- A bidirectional object graph — a parent navigation referencing children that reference the parent —
  serialises into a cycle, aborts the serialiser mid-stream and truncates the response. Break the
  cycle on the API side by ignoring the back-reference during serialisation.
- Exclude heavy child collections and large blob columns the panel never reads; they inflate every
  row for no benefit.
- An `unexpected EOF` from the datasource means truncated or invalid JSON, not an authentication or
  query problem. Fetch the raw response before changing the panel.
- Apply list filters server-side through optional query parameters, treating a whitespace value as no
  filter. Unknown query parameters are ignored by most API frameworks, so a dashboard can be wired
  ahead of the API deployment.

## No Data Is Not Always a Bug

- A panel showing no data and no warning icon usually means the query genuinely returned zero rows —
  nothing happened in the window yet.
- A panel showing a warning or alert icon means the query errored: authentication failure, a bad
  parameter, or invalid JSON. Distinguish the two before changing anything.
- Widen the time range and re-run before concluding the query is wrong. Comparing a narrow window
  against a wide one separates an empty window from a broken query.

## Debugging Toolkit

- Read the live datasource definition and confirm the resolved user or token is a real value rather
  than a placeholder left over from provisioning.
- Reproduce a panel by posting an inline query target to Grafana's query API and reading the returned
  error, row count and notices. This isolates the datasource from the dashboard JSON.
- Fetch the live dashboard by UID to inspect the URLs and variable values Grafana actually resolved,
  which often differ from the JSON in the repository.
- Hit the upstream endpoint directly from inside the cluster with a throwaway client pod, passing
  credentials through environment variables so they are never printed:

  ```text
  kubectl run tmp-curl -n <namespace> --image=curlimages/curl --rm -i \
    --env=U=... --env=P=... -- sh -c '...'
  ```

- Address in-cluster endpoints as `<service>.<namespace>.svc.cluster.local`, never by pod IP.
- When hand-building epoch millisecond bounds for a query, check the year. A stale-year epoch
  silently returns zero rows against current data.
