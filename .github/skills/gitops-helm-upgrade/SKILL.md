---
name: gitops-helm-upgrade
description: 'Upgrade third-party Helm releases managed through GitOps, including Argo CD Applications and ApplicationSets, versioned values snapshots, bootstrap pins and generated inventories. Use when checking or applying upstream chart updates; kubernetes-helm owns chart authoring and packaging, and gitops-repository-structure owns discovery and ownership migrations.'
argument-hint: '[charts=names|all] [mode=check|upgrade]'
compatibility: 'Requires Git, access to authoritative upstream chart releases, and the consuming repository validation and inventory tools when configured.'
---

# GitOps Helm Upgrades

Update the complete desired-state contract for each requested third-party chart, not only its
version pin. Keep deployment coordinates, repository layout, first-party exclusions, bootstrap
exceptions and inventory commands in the consuming repository's instructions or local skill adapter.
Never copy private operational profiles into this shared skill.

## Boundaries And Inputs

- `check` is read-only: discover pins, verify upstream releases and report proposed changes.
- `upgrade` edits local desired state. It does not authorize tests, commits, pushes, publication
  or live cluster operations.
- Resolve requested chart names or Application aliases, target versions when supplied, the local
  operational profile, and any commit decision already given by the user.
- An `all` request covers third-party charts only. Resolve first-party ownership from the local
  profile and source provenance, not a hardcoded registry owner. Stop on ambiguous ownership.
- Use [kubernetes-helm](../kubernetes-helm/SKILL.md) for chart authoring, dependency contracts,
  packaging and rendering details. Use
  [gitops-repository-structure](../gitops-repository-structure/SKILL.md) for discovery, ownership or
  namespace migrations; do not combine those changes with a routine chart bump.

## 1. Establish The Batch

1. Read the target repository's instructions and operational profile; preserve unrelated work.
2. Resolve the commit decision before upgrade research or edits if it has not already been given:
   commit each chart separately at the end, or leave the batch uncommitted. This decision never
   authorizes a push and does not override other Git safeguards.
3. Normalize aliases, remove duplicates and retain request order. Inventory current versions once
   using the repository's configured inventory command, or inspect the manifests directly when
   no generator exists. Read-only checks must not regenerate tracked output.
4. Map every chart to its owning Applications, ApplicationSets, generated inputs, values references,
   bootstrap/provisioning definitions and documentation. Search available infrastructure
   repositories as well as the GitOps checkout; do not create another checkout implicitly.
5. Execute directly unless substantial independent work warrants delegation. If work is delegated,
   assign disjoint file ownership and reserve shared bootstrap files and inventory output for
   central integration. Delegates must not commit or regenerate shared inventory.

## 2. Verify The Target Release

For each chart:

1. Inspect both single-source and multi-source definitions and their actual generator/template
   inputs. Record repository or OCI source, chart, current pin, release name, destination namespace,
   values precedence and inline overrides. Retained inactive definitions follow local policy.
2. Verify the requested or latest stable chart version at its authoritative repository or registry.
   An unresolved OCI inventory row is not evidence that the deployed version is current.
3. Read intervening release notes for breaking changes, removed settings/APIs, Kubernetes support,
   CRD changes and migration sequencing. Distinguish chart version from application version.
4. Obtain the exact target release's upstream values. Stop if the release or authoritative values
   cannot be verified; do not guess a version or silently preserve a stale snapshot.
5. Start with release notes and target values. Inspect templates, CRDs or old/new renderings when
   a migration, changed override or unresolved compatibility question requires that evidence;
   avoid exhaustive chart extraction for an otherwise routine bump.

## 3. Synchronize Desired State And Bootstrap Pins

1. Rename versioned upstream values snapshots with `git mv` before replacing their contents.
   Preserve the local extension and discovery exclusions. Use complete target defaults rather
   than merging deployment overrides into the upstream snapshot; do not introduce a snapshot
   where the repository does not use one.
2. Update every relevant chart pin and renamed values reference at its source of truth. Preserve
   release names, namespaces and resource identity; never hand-edit generated output instead of
   its owning input.
3. Compare effective overrides with the target schema/defaults and release notes. Preserve
   intentional settings, migrate removed or renamed settings, and retain useful upstream comments
   and property ordering.
   Argo CD uses `valuesObject` instead of `values` when both exist, and Kubernetes prunes explicit
   null object keys. Null-sensitive overrides require the complete inline payload in `helm.values`
   YAML; verify the persisted live source rather than splitting overrides between both fields.
4. Synchronize every active bootstrap or provisioning pin that installs the same release, including
   bootstrap-only definitions the local profile designates. Preserve deliberate non-installation
   and adoption boundaries; do not add a second controller or release merely for symmetry.
5. Update directly related version documentation. For a required migration, record its approved
   sequencing and rollback constraints. Do not execute live migration steps as an incidental edit.
6. Keep temporary downloads/extractions outside the repository and clean up only the files
   created for this task.

## 4. Validate And Regenerate Inventory

1. Integrate the complete batch before validating shared files. Check YAML syntax, duplicate keys,
   values references, source pins, bootstrap alignment and accidental resource-identity changes.
2. Propose the smallest repository-configured render/schema/lint checks that cover changed
   overrides and migration paths. Obtain approval before tests or cluster-connected validation.
   A syntactically valid version pin alone does not establish upgrade compatibility.
   Match the deployment renderer's Helm version, Kubernetes capabilities and actual values
   precedence; inspect service-level behavior as well as resource readiness when deployment is approved.
3. Run `git diff --check`; check for stale versioned filenames and inconsistent pins. Git may
   display a heavily replaced snapshot as delete/add despite using `git mv`; inspect history and
   content rather than repeatedly moving the file to force a similarity heuristic.
4. After an upgrade batch, regenerate any required tracked inventory once using the configured
   repository command. Verify requested rows and report unresolved upstream status explicitly.
   Keep the generator and its scheduled workflow repository-owned, outside the skill package.
5. Report unexecuted tests, rendering or runtime checks as gaps, never as passing validation.

## 5. Commit And Report

When commits are authorized, commit each chart's manifests, snapshots, bootstrap pins and direct
documentation together. Assign shared-file hunks to the relevant chart without staging another
chart's changes; put indivisible generated batch inventory in a separate final commit.
If changes cannot be isolated safely, stop and resolve the grouping rather than mixing upgrades.

Report old/new chart versions, affected consumers and pins, migrations, inventory status,
validation and remaining operator actions. Leave work uncommitted when requested. A local
desired-state update is not evidence of deployment or runtime health.

## Maintaining This Skill

- Argo CD single/multi-source and ApplicationSet generator semantics, especially values precedence
  and generated inputs.
- Helm/OCI release discovery, upstream values retrieval, CRD upgrade constraints and schema tools.
- Consumer operational profiles when discovery paths, first-party ownership, bootstrap exceptions
  or inventory contracts change; keep those values local.
