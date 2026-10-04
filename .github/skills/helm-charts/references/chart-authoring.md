# Chart Authoring Reference

## Chart Boundaries

Use a reusable chart when multiple consumers share a stable Kubernetes contract. Keep a chart local
when it packages one application's templates, one umbrella's dashboard bundle, or repository-specific
behavior. Promote a local chart only after it has independent consumers and a compatibility contract.

An umbrella chart composes dependencies and owns their aliases, conditions, cross-chart defaults,
and operator-facing installation experience. It does not copy dependency templates or schemas.

When several aliases share one application host, the umbrella can own one host-level resource while
the aliases own paths and backends. For example, an F5 mergeable master Ingress belongs in the
application umbrella, while workload dependencies render minions. A host shared by unrelated
applications belongs in the consuming GitOps repository instead.

## Metadata and Versions

Every `Chart.yaml` defines:

* `apiVersion: v2`
* a stable lowercase `name`
* a concise user-facing `description`
* an explicit `type`, normally `application`
* a Semantic Versioning `version`
* a quoted `appVersion` describing the packaged application or contract

Determine version ownership before editing. Some application charts receive their version during
release packaging, while independently published charts use the committed `Chart.yaml` version.
Preserve that model and document it locally.

Increment an independently versioned chart whenever its packaged contents change. Never move or
reuse a released chart version or OCI tag. Use repository-specific tag conventions when source tags
identify individual charts.

Do not change `appVersion` merely because the chart version changes. Trace every use of
`.Chart.AppVersion`, including default image tags and labels. Preserve it when the packaged
application is unchanged; otherwise an additive chart feature can silently change runtime images
for consumers that omit `image.tag`.

Publish public application charts under `ghcr.io/<owner>/charts/<chart-name>`. Pass the full final
coordinate to shared packaging workflows. Keep the chart directory basename, `Chart.yaml` name, and
final OCI segment identical because packaging derives and publishes that name. The account-level
namespace is shared across source repositories, so names must be globally unique. Use the
application name for its primary chart and `<application>-<purpose>` for ancillary charts instead of
generic names such as `dashboards`.

## Values and Schemas

Keep `values.yaml`, `values.schema.json`, templates, and README examples synchronized.

* Declare JSON Schema Draft-07 explicitly.
* Validate owned keys, types, enums, ranges, patterns, and required relationships.
* Keep reusable and umbrella roots open when aliases, dependency values, or compatible extensions
  require it.
* Use `additionalProperties: false` for small, fully owned objects where unknown keys are errors.
* Account for Helm's injected `global` values before closing a chart root.
* Keep schema annotations next to their values when a pinned generator treats those annotations as
  the source of truth.
* Regenerate schemas with the repository-pinned tool and review the generated diff.

Prefer template guards for relationships that JSON Schema cannot express clearly. Error messages
should name the conflicting values and the supported alternatives.

When values must reference a chart-generated name, expose a typed computed-value contract rather
than asking consumers to reconstruct Helm naming:

```yaml
computedAnnotations:
  example.com/backend-service:
    valueFrom: serviceName
```

Resolve `serviceName` through the same fullname helper used by the Service and Ingress backend.
Reject duplicate literal and computed keys so precedence is never implicit. Keep the mechanism
generic: controller-specific annotation names and migration policy remain consumer values. Avoid
whole-map `tpl`, which grants broad template evaluation and weakens schema validation.

## Dependencies

Choose the source according to the reuse boundary:

* Pin shared charts to an exact published OCI version.
* Use `file://` for application-specific charts consumed only by the same repository or umbrella.
* Use aliases when one dependency appears more than once for distinct responsibilities.
* Put each dependency condition on the alias path that consumers configure.

After dependency changes, update `Chart.lock` with the repository's standard Helm command. Do not
commit generated dependency archives unless the repository explicitly treats them as source.

Before changing a consumer pin, verify the exact immutable source tag/release and pull the OCI
package by version. Do not consume an intended version while its default-branch publication is
still running.

## Templates

Expose Kubernetes-native settings consistently across pod-producing resources:

* image and pull policy
* command and arguments
* environment variables and mounted configuration
* resources and security contexts
* service account and pod metadata
* node selectors, tolerations, affinity, and topology spread constraints
* persistence, ephemeral storage, and volume mounts

Keep primary workload modes mutually exclusive. Companion resources that must run independently
need their own explicit lifecycle and ownership.

Use stable helper names and deterministic resource names. Preserve selectors, immutable fields,
resource identity, and upgrade behavior during migrations unless the change explicitly replaces
them.

For optional booleans that default to true, distinguish absence from explicit false with `hasKey`;
Helm's `default` function treats false as empty. In ranged templates that render multiple YAML
documents, preserve a newline before each `---` and test at least two entries so whitespace trimming
cannot concatenate documents.

## Fixtures and Package Contents

Store representative chart-testing values under `ci/` in each chart source directory. Include
fixtures for supported modes and important optional paths. Keep fixtures out of the published
package through `.helmignore`.

Package inspection should confirm that runtime files are present and maintainer-only fixtures,
temporary files, local dependencies, and secrets are absent.

## Documentation

Every chart README remains self-contained for consumers. Include the sections that apply:

1. chart purpose and dependency model;
2. Helm installation;
3. equivalent Argo CD source and values examples;
4. setup or activation steps;
5. configuration and complete default values;
6. persistence and operational behavior;
7. authoritative related project and platform links.

Pin the chart version in reproducible install examples. Use synthetic namespaces, images, endpoints,
and values. Explain whether an unpinned upgrade intentionally tracks the latest stable chart.

When a chart declares dependencies, keep a Mermaid graph showing the parent, each alias, and the
chart and version that alias resolves to. Update it with dependency changes.

The repository README should catalogue published charts with links to their chart READMEs, current
versions, OCI references, and concise purpose statements. Keep detailed configuration in the chart
README.
