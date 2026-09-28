---
description: 'Core Helm chart invariants and the boundary between shared authoring workflows and repository-specific contracts.'
applyTo: 'charts/**,**/*-helm/**'
---

# Helm Chart Authoring

Apply the generic Helm skill when creating, updating, migrating, auditing, packaging, documenting,
or validating a chart. This always-loaded file retains only invariants needed while editing chart
files; the skill owns the detailed workflow and reference material.

## Contract

* Treat each chart as a versioned package with explicit metadata, values, schema, dependencies,
  fixtures, documentation, and release ownership.
* Keep chart implementation and every affected contract surface synchronized in one change.
* Pin shared dependencies exactly. Keep application-specific singleton dependencies local.
* Preserve released chart versions and OCI tags. Never move or reuse them.
* Publish public application charts under `ghcr.io/<owner>/charts/<chart-name>`. Keep the chart
  directory basename, `Chart.yaml` name, and final OCI path segment identical and globally unique
  within the shared namespace.
* Keep representative chart-testing fixtures under `ci/` and exclude them from packages.
* Keep each chart README self-contained for consumers. Do not replace install, configuration, or
  operational guidance with a reference to internal Copilot customizations.
* Preserve resource and dashboard identity during migrations unless the change explicitly replaces
  it.

## Values and Templates

* Validate owned values with `values.schema.json`; let dependencies validate their own contracts.
* Keep reusable and umbrella schema roots open when aliases, dependency values, or compatible
  extensions require it.
* Expose Kubernetes-native scheduling, security, resources, persistence, and pod metadata
  consistently across pod-producing templates.
* Keep primary workload modes mutually exclusive and fail invalid combinations with actionable
  schema or template errors.

## Grafana Packages

* Keep dashboards as standalone JSON files and preserve established UIDs, ConfigMap names, keys, and
  folder placement.
* Never process dashboard JSON or alert rules with Helm `tpl`; use exact replacement for a small,
  approved placeholder set.
* Ensure only one release per environment emits a given dashboard UID.
* Keep dashboard queries, datasources, endpoints, alert behavior, and compatibility mappings in the
  consuming repository.

## Validation Boundary

Validate dependencies, schemas, representative rendering, invalid inputs, package contents,
documentation, and migration equivalence. Ask before running tests, chart-testing suites, registry
operations, cluster commands, or publication.
