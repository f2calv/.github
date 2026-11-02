---
name: containers-devcontainer
description: 'Create, update, align and validate Dev Containers: images, Features, lifecycle scripts, mounts, lockfiles, extensions and host/editor sync across repositories. Use when adding tooling or diagnosing a Dev Container that fails to start.'
argument-hint: 'mode={add|update|upgrade|reconcile|audit|align} [scope=repository-or-workspace]'
compatibility: 'Authoring is cross-platform. Rebuild validation requires Docker and VS Code Dev Containers or the Dev Container CLI.'
---

# Dev Container

## Overview

Build a development environment that matches the repository's actual responsibilities without
turning `devcontainer.json` into a universal workstation image. Start from the nearest compatible
repository or official template, add only required tools, and keep every downstream consumer of its
version fields synchronized.

The workspace uses four broad shapes:

* Language repositories use the matching language image and editor extensions.
* Infrastructure modules use a small base image plus explicit infrastructure Features.
* GitHub Actions and repository tooling use a general base image plus GitHub, JSON/YAML, and optional
  Docker tooling.
* GitOps repositories add only the cluster and configuration-management clients they operate.

These are selection guides, not templates to merge together.

## Prerequisites

* Read the target repository's Copilot instructions and `.editorconfig` before editing.
* Identify whether the request is to add, update, upgrade, audit, or align a devcontainer.
* Docker and a Dev Container implementation are required only for build validation.
* Never put credentials, identifiers, hostnames, or user-specific absolute paths in tracked files.
* Ask before running a devcontainer build, rebuild, or repository tests.

## Quick Start

```text
/containers-devcontainer add to this repository
/containers-devcontainer upgrade the Terraform and Helm tools
/containers-devcontainer reconcile after adding PowerShell tests
/containers-devcontainer align the sibling repositories
/containers-devcontainer audit this workspace for drift
/containers-devcontainer diagnose why the container fails to start here
```

| Mode | Contract |
| --- | --- |
| `add` | Create the smallest useful configuration and synchronize its consumers |
| `update` | Preserve the current model while applying the requested changes |
| `upgrade` | Check releases, compatibility, lock data, and version consumers |
| `reconcile` | Add missing safe capabilities implied by repository changes |
| `audit` | Make no edits; report findings and any dynamic checks not performed |
| `align` | Change only the explicitly declared repository set |

The skill does not watch the filesystem. Automatic reconciliation means that, whenever the skill
handles an `add`, `update`, `upgrade`, or `reconcile` request, it inspects the current Git diff and
repository state and includes safe missing capabilities in the same change. A deterministic check
outside Copilot requires a repository script or CI job; do not install a local Git hook by default.

## Workflow

Each step states the decisive rules; open the linked reference for the full procedure before
editing that surface.

### 1. Establish Scope

* Confirm the target repository or explicit workspace folders; do not scan unrelated clones.
* Inspect the devcontainer files, lifecycle scripts, lockfile, Dependabot, version consumers,
  extension lists, the branch diff and declared siblings, and record every synchronization point.
* For a public target, use only official or public precedents and never carry private topology.
* Detail: [container authoring](./references/container-authoring.md#establish-scope).

### 2. Choose the Container Model

* Use the simplest of official image, Dockerfile or Compose; never install one tool through more
  than one path, and keep the non-root user.
* Require explicit approval before host sockets, sensitive mounts, capabilities, security
  overrides or privileged mode.
* Detail: [container authoring](./references/container-authoring.md#choose-the-container-model);
  for a small tooling repository, start from the [minimal tooling example](./examples/minimal-tooling.md).

### 3. Author `devcontainer.json`

* Use exactly one of `image`, `build` or Compose; reference Features by supported major version and
  pin tool versions that CI or scripts read as authoritative.
* Verify Feature support for the base distribution and keep editor behavior in `.editorconfig`.
* Detail: [container authoring](./references/container-authoring.md#author-devcontainerjson).

### 4. Reconcile Repository Capabilities

* Infer Features and extensions from local execution evidence, not file extensions alone; never
  from CI-only commands.
* Add safe missing capabilities in `add`, `update`, `upgrade` and `reconcile`; ask before sensitive
  access; never remove one automatically.
* Detail, the evidence matrix and Pester module pinning:
  [capability reconciliation](./references/capability-reconciliation.md#reconcile-repository-capabilities).

### 5. Synchronize VS Code Extensions

* Treat `.vscode/extensions.json` as canonical and mirror it in `customizations.vscode.extensions`.
* Validate every ID against the Marketplace, prefer current direct extensions over packs, and
  document any host-only or container-only exception.
* Detail: [capability reconciliation](./references/capability-reconciliation.md#synchronize-vs-code-extensions).

### 6. Handle Mounts and Credentials

* Prefer the default workspace mount and Dev Container variables over literal paths.
* Default to no credential mounts; when approved, mount the narrowest files read-only where possible
  and never copy credentials into images or tracked files.
* Detail: [container authoring](./references/container-authoring.md#handle-mounts-and-credentials).

### 7. Design Lifecycle Scripts

* Keep lifecycle behavior in scripts; never authenticate, mutate remote systems or change clusters
  from hooks, and keep `postStartCommand` fast and idempotent.
* Do not create Python virtual environments or auto-install per-commit hooks.
* Detail, hook order and the reusable tool verifier: [lifecycle scripts](./references/lifecycle-scripts.md).

### 8. Synchronize Consumers

* Search for the old value and key before changing an image, Feature, option or tool version, and
  update every authoritative duplicate in the same change.
* Detail: [synchronization and validation](./references/synchronization-and-validation.md#synchronize-consumers).

### 9. Locking and Dependabot

* Use the owning Dependabot ecosystem; never hand-edit `devcontainer-lock.json`, and do not
  introduce a lockfile incidentally.
* Detail: [synchronization and validation](./references/synchronization-and-validation.md#locking-and-dependabot).

### 10. Validate

* Run cheap static checks first, ask before building or rebuilding, and report every dynamic check
  not performed; a parse alone is insufficient.
* Detail: [synchronization and validation](./references/synchronization-and-validation.md#validate).

### 11. Preserve Sibling Alignment

* Apply and validate shared changes across the entire declared sibling set; isolate deliberate
  deviations and commit per repository.
* Detail: [synchronization and validation](./references/synchronization-and-validation.md#preserve-sibling-alignment).

## Upgrade Procedure

Follow the [upgrade procedure](./references/synchronization-and-validation.md#upgrade-procedure):
inventory, reconcile, confirm compatibility, change the smallest authoritative set, regenerate lock
data, synchronize consumers, validate, ask before rebuilding and feed lessons back into this skill.

## Troubleshooting

When a configuration works on one workstation but not another, suspect the host before the
repository and gather evidence before editing tracked files. Follow the
[troubleshooting guide](./references/troubleshooting.md) for the failed-start procedure and the
symptom table.

## References

* [Dev Container JSON reference](https://containers.dev/implementors/json_reference/)
* [Dev Container Features](https://containers.dev/features)
* [Images, Dockerfiles, and Docker Compose](https://containers.dev/guide/dockerfile)

## Maintaining This Skill

* Base image, Feature and tool versions, and the lockfile refresh in the
  [upgrade procedure](./references/synchronization-and-validation.md#upgrade-procedure).
* Lifecycle-script, mount and host/editor-sync behaviour whenever a container fails to start for a
  new reason, recorded in the [troubleshooting guide](./references/troubleshooting.md).
* Keep the minimal example's Feature options, Pester version, lifecycle script and extension lists
  synchronized; distinguish static validation from an approved container rebuild.
* Keep the SKILL.md step summaries in step with the reference files they link.
