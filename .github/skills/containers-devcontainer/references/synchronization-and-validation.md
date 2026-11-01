# Synchronization and Validation

Synchronize version consumers, lock data and siblings, validate changes and follow the upgrade procedure.

## Synchronize Consumers

Before changing an image, Feature, option, or tool version, search for its old value and key.

Common consumers are:

* Actions or workflows that extract tool versions from `devcontainer.json`;
* language SDK pins and infrastructure version constraints;
* package managers, bootstrap definitions, and README commands;
* sibling repositories maintained for cross-language comparison.

Update every authoritative duplicate in the same change. If values intentionally differ, document
which file owns each version rather than forcing equality.

## Locking and Dependabot

Use the ecosystem that owns each dependency:

* `devcontainers` with `directory: /` updates Feature declarations and the Feature lockfile.
* `docker` covers base images in a devcontainer Dockerfile.
* `docker-compose` covers service images in a devcontainer Compose file.

Preserve the repository's existing schedule and grouping conventions, and do not add duplicate
entries.

* Treat `devcontainer-lock.json` as generated resolution data; never hand-edit versions, digests, or
  integrity values.
* If a lockfile is tracked, regenerate it using the project's Dev Container implementation after
  changing Features and commit it with `devcontainer.json`.
* If no lockfile is tracked, do not introduce one incidentally. Decide the policy explicitly and
  apply it consistently to aligned siblings.
* Validate automated Feature updates like manual changes.

## Validate

Run cheap checks first:

1. Parse `devcontainer.json` with a JSON-with-comments-aware parser.
2. Check diagnostics and `git diff --check`.
3. Run `shellcheck` on changed lifecycle scripts when available.
4. Verify referenced scripts, Dockerfiles, Compose files, mounts, and extensions.
5. Query the VS Code Marketplace for every recommended extension. Fail validation for missing or
  deprecated IDs, and review replacement guidance plus extension-pack/dependency metadata.
6. Search for stale versions in CI, docs, bootstrap files, and sibling repositories.
7. Compare `.vscode/extensions.json` recommendations with Dev Container extensions
  case-insensitively and account for every intentional exception.
8. Verify every inferred local command is available from the image, one Feature, or one lifecycle
  installer, without duplicate installation paths.
9. Confirm Dependabot covers the devcontainer directory.
10. If a lockfile is tracked, verify every configured Feature and its transitive dependency closure
  is present, with no missing, stale, or unreachable records.
11. Ask before building or rebuilding.
12. After approval, rebuild from a clean cache for image or Feature upgrades.
13. Inside the rebuilt container, print required tool versions, verify recommended extensions are
   installed in the expected extension host, and run only approved checks.

A parse alone is insufficient for an implementation. When build approval or tooling is unavailable,
report the unperformed dynamic checks rather than claiming them. An audit is complete when it reports
the static findings and clearly identifies every dynamic check not performed.

## Preserve Sibling Alignment

When repositories intentionally mirror each other:

* Compare image families, Feature sets, lifecycle responsibilities, mounts, and common extensions.
* Keep shared lifecycle scripts byte-identical where required.
* Isolate language-specific deviations in clearly marked sections.
* Apply and validate the change across the entire declared sibling set.
* Commit per repository when histories are separate.

## Upgrade Procedure

1. Inventory the image, Features, options, lockfile, Dependabot, and version consumers.
2. Reconcile changed repository capabilities and host/container extension parity.
3. Read official release notes and confirm base-distribution compatibility.
4. Change the smallest authoritative set of fields.
5. Regenerate tracked lock data rather than editing it.
6. Synchronize CI, documentation, and siblings.
7. Run parse, lint, reference, extension-set, and diff checks.
8. Ask before rebuilding.
9. Rebuild and verify tool versions and extensions after approval.
10. Review lessons from the completed work and flow durable corrections, replacement guidance and
  validation improvements back into this skill before reporting completion.
11. Report versions, capability decisions, intentional exceptions, validation, and manual host setup.
