# Helm Validation Reference

## Plan the Matrix

Map each changed value or template branch to a representative fixture before running commands.
Cover every changed workload mode, enabled dependency, optional resource, persistence path, and
dashboard condition. Add deliberately invalid cases for schema constraints and template guards.

## Suggested Commands

Use repository wrappers when they pin tools or add required arguments. Otherwise adapt this sequence:

```console
helm dependency update <chart>
helm lint <chart> --values <chart>/ci/<fixture>.yaml
helm template example <chart> --namespace my-namespace --values <chart>/ci/<fixture>.yaml
helm package <chart> --destination <temporary-directory>
```

Run the repository's chart-testing, schema generation, documentation generation, and pre-commit
commands when they cover the changed surface. Ask before running tests or suites.

Do not publish packages, log into registries, synchronize Argo CD, or access a cluster as validation
unless the user explicitly authorizes that operation.

## Assertions

Check more than command exit codes:

* rendered resource kinds, names, namespaces, labels, selectors, annotations, and ownership;
* image references, commands, ports, probes, environment, mounts, scheduling, and security settings;
* dependency aliases, conditions, and propagated values;
* absent resources when features are disabled;
* schema and guard failures with actionable messages;
* dashboard ConfigMap names, keys, labels, folders, UIDs, and literal Grafana tokens;
* package contents and exclusions;
* README examples and embedded defaults against the source values;
* version consistency across metadata, catalogues, workflows, and consumers.

For master/minion or other split ownership models, assert one host owner, no paths on the master,
no TLS on minions, unique paths, correct namespaces, and exact rendered backend Service names.
Render at least two master entries to catch YAML document-separator whitespace bugs.

During migrations, render the old and new implementations with equivalent inputs and compare
normalized manifests. Account for every difference as intentional, generated noise, or a defect.

For backward-compatible chart features:

1. render every existing fixture from the previous immutable source and the candidate;
2. normalize only expected packaging metadata such as `helm.sh/chart`;
3. compare the remaining manifests byte-for-byte or structurally;
4. investigate image changes before normalizing `app.kubernetes.io/version`, because `appVersion`
   often supplies a default image tag;
5. render new success fixtures and assert exact generated names and annotations;
6. run expected failures from a location chart-testing does not treat as a success fixture.

When schema generation is chart-scoped, verify the changed key exists in the generated schema. A
green generator hook is insufficient if dependency filtering caused the local chart to be skipped.

## Handoff

Report:

* files and contracts changed;
* fixtures and modes covered;
* commands run and their results;
* expected-failure cases checked;
* commands not run and why;
* version, publication, or rollout actions still requiring authorization.
