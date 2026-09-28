---
name: helm-charts
description: 'Create, update, migrate, audit, package and validate Helm and umbrella charts: values schemas, dependencies, OCI releases, chart-testing, Argo CD examples and Grafana dashboard ConfigMaps. Use for Chart.yaml, values.yaml, templates or chart releases.'
argument-hint: 'mode={create|update|migrate|audit|package} [path=chart-or-repository]'
user-invocable: true
compatibility: 'Authoring is cross-platform. Validation requires Helm 3 and any repository-pinned schema, chart-testing, or documentation tools.'
---

# Helm Charts

## Overview

Create and maintain Helm charts as independently versioned packages with explicit values contracts,
repeatable dependency resolution, consumer-focused documentation, and representative validation.
Keep reusable chart mechanics generic. Keep application names, endpoints, credentials, deployment
topology, dashboard queries, and release automation details in the consuming repository.

## Prerequisites

* Read the target repository instructions, chart README, release workflow, and existing chart
  conventions before editing.
* Inspect the complete chart, its parents and consumers, not only the requested template.
* Use the repository-pinned Helm, schema generator, chart-testing, and documentation tool versions.
* Ask before running tests, chart-testing suites, cluster operations, package publication, or commands
  that access registries, GitOps repositories, or live releases.
* Never put credentials, private repository coordinates, real endpoints, or environment identifiers
  in chart defaults, fixtures, examples, rendered output, or logs.

## Quick Start

```text
/helm-charts create a reusable application chart
/helm-charts update charts/example for a new workload mode
/helm-charts migrate these manifests into an umbrella chart
/helm-charts audit the workspace charts
/helm-charts package the Grafana dashboards in this chart
```

| Mode | Contract |
| --- | --- |
| `create` | Define the chart boundary, author metadata, values, schema, templates, fixtures, and documentation |
| `update` | Preserve the public contract unless the request changes it; synchronize every affected surface |
| `migrate` | Compare source and rendered resources, preserve identity where required, and account for each difference |
| `audit` | Make no edits; report findings, evidence, validation gaps, and repository-specific exceptions |
| `package` | Prepare dependencies or an OCI package without publishing unless the user explicitly authorizes it |

## Workflow

### 1. Establish Scope and Ownership

1. Identify every chart affected by the change, including leaf charts, umbrella charts, dependency
   aliases, dashboard bundles, and repository catalogue entries.
2. Classify each chart as reusable, application-specific, umbrella, or dashboard-only.
3. Record its version authority, publication path, dependency boundary, supported workload modes,
   and downstream consumers.
4. Separate shared Helm mechanics from repository-specific behavior. Do not move consumer-visible
   installation or configuration guidance out of a published chart README.
5. Preserve unrelated working-tree changes and existing resource identity unless the request
   explicitly changes it.

### 2. Design or Update the Contract

Use [the chart authoring reference](references/chart-authoring.md) for metadata, values schemas,
dependencies, templates, documentation, fixtures, and release boundaries.

* Keep common installations concise and explicit.
* Put Kubernetes-native scheduling, security, persistence, and resource settings behind typed values.
* Keep mutually exclusive workload modes and conflicting settings guarded by schemas or template
  failures.
* Let each dependency validate its own values. An umbrella chart validates the structure it owns
  without copying a subchart schema.
* Treat chart behavior, metadata, values, schemas, lock files, examples, and documentation as one
  public contract.

### 3. Handle Grafana Dashboard Charts

Use [the Grafana dashboard packaging reference](references/grafana-dashboards.md) when a chart emits
dashboard ConfigMaps, alert rules, or datasource placeholders.

* Keep dashboard JSON as standalone, lintable files.
* Preserve established dashboard UIDs, ConfigMap names, data keys, and folder placement.
* Never pass dashboard or alert content through Helm `tpl`.
* Make one release per environment responsible for each dashboard UID.
* Keep dashboard queries, datasource UIDs, endpoints, alert semantics, and compatibility mappings
  in the consuming repository.

### 4. Synchronize the Change

Update every affected surface in the same change:

* `Chart.yaml`, `values.yaml`, and `values.schema.json`
* templates, helpers, notes, and `.helmignore`
* `Chart.lock` and dependency aliases or conditions
* `ci/` fixtures and repository validation configuration
* chart README defaults, examples, dependency diagrams, and repository catalogue entries
* release workflows, version pins, and consumer documentation when their contract changes

Do not bump or rewrite versions mechanically. Follow the repository's version authority and release
model. Released chart versions and OCI tags are immutable.

### 5. Validate

Follow [the validation reference](references/validation.md). Propose the smallest command set that
covers the changed contract, then obtain approval before running tests or suites.

At minimum, validation should cover:

1. dependency and lock-file consistency;
2. lint and schema validation for representative fixtures;
3. rendered manifests for each changed mode and important conditional path;
4. expected failures for invalid or conflicting values;
5. packaged contents, including `.helmignore` exclusions;
6. documentation and version consistency;
7. semantic comparison with the previous rendering during migrations.

Report commands that were not run and the reason. A successful `helm lint` alone does not prove
conditional templates, invalid inputs, package contents, or migration equivalence.

## Troubleshooting

* If a dependency alias renders nothing, verify the alias key, `condition`, and parent values path.
* If schema validation rejects dependency values, check whether the umbrella schema incorrectly
  closes or duplicates the dependency contract.
* If packaged fixtures or source files appear in the archive, review `.helmignore` and inspect the
  generated package.
* If Grafana tokens fail Helm parsing, remove whole-document `tpl` and use exact placeholder
  replacement.
* If a dashboard appears twice, find every release emitting the same UID and assign one owner per
  environment.
* If Argo CD renders different resources than the CLI example, compare chart version, dependency
  lock, values precedence, namespace, and capabilities.
