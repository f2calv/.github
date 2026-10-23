# Executable Helm Contract Example

The [example-message chart](./example-message/README.md) is a deliberately small, dependency-free
fixture. It connects values, a Draft-07 schema, one conditional template, valid and invalid inputs,
and package exclusions without inventing a full workload chart.

## Contract Matrix

| Input | Lint/render expectation | Resource assertion |
| --- | --- | --- |
| Defaults | Success | Exactly `example/example-message`, kind ConfigMap, default literal text |
| `ci/custom-values.yaml` | Success | Same identity, custom text preserved byte-for-byte after YAML parsing |
| `ci/disabled-values.yaml` | Success | Zero resources; explicit `false` is not replaced with `true` |
| `tests/invalid/empty-text.yaml` | Schema failure | Error identifies `text`; no successful manifest |
| `tests/invalid/string-boolean.yaml` | Schema failure | Error identifies `enabled` |
| `tests/invalid/unknown-key.yaml` | Schema failure | Error identifies `enabeld` |
| Local package | Success | Required runtime files present; `ci/` and `tests/` absent |

Run commands from the chart directory using the consuming repository's pinned Helm version where
one exists. The fixture uses ordinary Helm v3/v4 functionality and needs no registry or cluster.
Use the exact commands in its README; do not add `--validate`, dependency downloads or an install
to an offline check accidentally.

## Reuse Without Duplication

* Copy the fixture's contract pattern, not its synthetic chart identity, into a real chart.
* Update the values, schema, templates, fixtures and consumer README together.
* Let a generator own the schema when the target repository already uses one. This fixture's small
  schema is hand-authored; it does not introduce a second schema generator.
* Schema validation handles every invalid relationship here, so no duplicate template guard is
  needed. Add a template `fail` only when a real relationship needs it, with its own negative case.
* There is no `Chart.lock` because there are no dependencies. Do not manufacture lockfiles or
  update external chart pins just to validate this example.
* The source fixture is not a released chart product. Its local package version makes package
  inspection repeatable, not evidence of OCI publication.

The central regression suite renders the actual chart and parses the result with `yq`. The generic
YAML syntax hook excludes only this Go-template directory; Helm rendering, parsed manifests and
negative schema cases cover it instead. The other YAML assets still pass the ordinary YAML hook.
