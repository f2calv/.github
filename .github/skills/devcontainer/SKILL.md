---
name: devcontainer
description: 'Create, update, reconcile, align, and validate Dev Containers. Use when adding file types that need local tools or VS Code extensions, changing images, Features, lifecycle scripts, mounts, lockfiles, or synchronizing host/container editor behavior, Dependabot, CI, documentation, and sibling repositories.'
argument-hint: 'mode={add|update|upgrade|reconcile|audit|align} [scope=repository-or-workspace]'
user-invocable: true
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
/devcontainer add to this repository
/devcontainer upgrade the Terraform and Helm tools
/devcontainer reconcile after adding PowerShell tests
/devcontainer align the sibling repositories
/devcontainer audit this workspace for drift
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

### 1. Establish Scope

1. Confirm the target repository or explicit workspace folders. Do not scan unrelated clones.
2. Inspect:
    * `.devcontainer/devcontainer.json`;
    * any devcontainer Dockerfile or Compose files;
    * lifecycle scripts under `.devcontainer/`;
    * `devcontainer-lock.json`, when tracked;
    * `.github/dependabot.yml`;
    * workflows, actions, scripts, and docs that read devcontainer fields;
    * `.vscode/extensions.json` and container-specific VS Code customizations;
    * added and renamed files in the working-tree and branch diff;
    * sibling repositories required to remain aligned.
3. Determine the visibility of the target and any precedent. For a public target, use official or
  public precedents and never carry private topology, mounts, registries, or internal tooling into
  tracked content.
4. Select the nearest compatible precedent by repository role and language.
5. Record every synchronization point before editing.

### 2. Choose the Container Model

| Model | Use when |
| --- | --- |
| Official image | A language or base image plus Features is sufficient |
| Dockerfile | Native packages or image-layer customization are required |
| Docker Compose | Development needs additional services such as a database or emulator |

* Use the simplest model that satisfies the repository.
* Do not use Compose merely to run Docker commands from the container.
* Do not install one tool through the image, a Feature, and a lifecycle script.
* Keep the non-root user unless a concrete tool requires otherwise.
* Add capabilities, security options, or privileged mode only for a demonstrated runtime need.
* Require explicit approval before adding host sockets, sensitive mounts, capabilities, security
  overrides, or privileged mode. Docker socket access is effectively host-root access.

### 3. Author `devcontainer.json`

Treat the file as JSON with comments and preserve its local style.

* Set a concise role-based `name`.
* Use exactly one of `image`, `build`, or the Compose properties.
* Reference Features by supported major version so Dependabot can update them.
* Pin concrete tool versions when CI or another script reads the Feature option as authoritative.
* Use `latest` only where reproducibility and environment parity do not matter.
* Disable unused tools in combined Features.
* Verify each Feature supports the selected base distribution. Distribution upgrades can require
  changed Feature options, especially for Docker client packages.
* Install only extensions needed for the repository's languages and workflows.
* Keep editor behavior in `.editorconfig` where possible; reserve VS Code settings for
  container-specific behavior.

### 4. Reconcile Repository Capabilities

Infer capabilities from what contributors must run locally, not from file extensions alone.

1. Inventory added and renamed files from the current Git diff, then scan the complete repository
   so one new file is interpreted in its existing context.
2. Find execution evidence in lifecycle scripts, developer commands, package manifests,
   `.pre-commit-config.yaml`, READMEs, and local validation scripts.
3. Classify each finding as:
   * editor support;
   * local runtime or CLI support;
   * CI-only support;
   * sensitive host access.
4. In `add`, `update`, `upgrade`, and `reconcile` modes, add safe missing Features and extensions in
   the same change. Ask before sensitive access. In `audit` mode, report only.
5. Never remove a Feature or extension automatically. Report apparently unused capabilities and
   require confirmation before removal.

Use this evidence matrix:

| Repository evidence | Editor action | Feature or local-tool action |
| --- | --- | --- |
| Locally executed `*.ps1` or a lifecycle command invoking `pwsh` | Add `ms-vscode.powershell` | Add `ghcr.io/devcontainers/features/powershell:2` |
| `*.Tests.ps1` or Pester module requirements | Add `ms-vscode.powershell` | Configure PowerShell `modules` with `Pester==<required-version>` |
| YAML authored in the repository | Add `redhat.vscode-yaml` | None unless local commands invoke `yq` |
| JSON authored in the repository | Use VS Code's built-in JSON support | None unless local commands invoke `jq` |
| `*.http` or `*.rest` request files | Add `humao.rest-client` | None; the extension executes requests |
| Local scripts or documented validation invoking `jq` or `yq` | No additional extension | Add `ghcr.io/eitsupi/devcontainer-features/jq-likes:2` |
| `*.tf` developed locally | Add `hashicorp.terraform` | Add the Terraform Feature and synchronize its version constraints |
| `Chart.yaml` or locally run Helm validation | Add the established Helm extension | Add or configure the Kubectl/Helm Feature |
| Dockerfile or Compose authoring | Add the established Containers extension | Add Docker access only when contributors run Docker inside the container |
| GitHub Actions authoring | Add `github.vscode-github-actions` | Add GitHub CLI only when local scripts or documented workflows invoke `gh` |
| Language manifest or source files | Add the established language extensions | Prefer the matching base image; use a language Feature only when needed |

Do not infer `jq-likes` from a YAML or JSON file alone. Do not infer local Features from commands
that run only in CI. A production Dockerfile does not by itself justify host Docker-socket access.

The official PowerShell Feature installs modules through a comma-separated `modules` option. There
is no separate official Pester Feature. Extract the required Pester version from `#Requires`, module
manifests, test runners, or CI, preserve any existing modules, and use an exact module version:

```jsonc
"ghcr.io/devcontainers/features/powershell:2": {
  "modules": "Pester==5.7.1"
}
```

Before adding a Feature, verify the image does not already provide the executable and that another
Feature or lifecycle command does not install it. Preserve established Feature IDs and option names
within aligned repository families.

### 5. Synchronize VS Code Extensions

Treat `.vscode/extensions.json` as the canonical repository recommendation set for contributors
working on the host. Mirror its compatible `recommendations` set in
`customizations.vscode.extensions` so the same extensions are installed inside the Dev Container.
This duplication is deliberate: workspace recommendations suggest extensions, while Dev Container
customizations install them in the remote environment.

* When adding a shared extension, update both files in the same change.
* Compare extension IDs case-insensitively as sets. Preserve the repository's established grouping
  and comments; order alone is not drift.
* If `.vscode/extensions.json` is absent, create it when the container declares extensions that are
  also useful outside the container.
* Verify an extension ID exists and supports the required local or remote extension host before
  adding it.
* Do not copy `unwantedRecommendations` into the Dev Container extension list.
* Allow host-only or container-only extensions only for a demonstrated compatibility or execution
  reason. Document the exception beside the relevant list and report it during reconciliation.
* Do not add an extension only because it is personally preferred. Recommendations describe the
  repository's supported workflows.

When an extension is supplied automatically by a Feature, still include it in both explicit lists
when host/container parity is required. Explicit lists make drift reviewable and do not depend on a
Feature's implicit customization remaining unchanged.

### 6. Handle Mounts and Credentials

* Prefer the default workspace mount. Bind a wider source root only for intentional sibling work.
* Use Dev Container variables such as `${localEnv:HOME}` and `${localEnv:USERPROFILE}` rather than
  literal home paths or user names.
* Mount kubeconfig, SSH, cloud CLI, or similar directories only when normal development needs them.
* Default to no credential mounts. When approved, mount the narrowest files possible, use
  least-privilege credentials, and do not start untrusted configurations with host credentials
  attached.
* Use read-only mounts where the container does not need to modify host files.
* Never copy credentials into images or commit secrets in environment settings, Compose files,
  Dockerfiles, examples, or lifecycle scripts.
* Document host prerequisites and fail clearly when a required mount is absent.

### 7. Design Lifecycle Scripts

Keep lifecycle behavior in scripts rather than long JSON command strings.

Lifecycle order is `initializeCommand`, `onCreateCommand`, `updateContentCommand`,
`postCreateCommand`, `postStartCommand`, then `postAttachCommand`.

* `initializeCommand` runs on the host before creation. Keep it portable and free of secrets.
* `onCreateCommand` runs in the container during its first creation.
* `updateContentCommand` runs when workspace content is created or updated. Put dependency
  restoration here when it must follow content changes.
* `postCreateCommand` runs after creation and content setup. Use it for final one-time setup and
  concise tool summaries.
* `postStartCommand` runs on every start. Keep it fast, idempotent, and free of repository churn.
* `postAttachCommand` runs on every editor attach and should contain only attach-specific work.
* Never authenticate, mutate remote systems, apply infrastructure, or change clusters from hooks.
* Avoid unconditional operating-system upgrades on every start; they are slow and nondeterministic.
* Do not auto-install per-commit hooks. Document manual linting and optionally offer
  `pre-commit install --hook-type pre-push --install-hooks`.
* Follow the repository's shell instructions: strict error handling, quoted expansions, validated
  inputs, and clear diagnostics.
* A script invoked through `bash` or `sh` does not require an executable bit.

### 8. Synchronize Consumers

Before changing an image, Feature, option, or tool version, search for its old value and key.

Common consumers are:

* Actions or workflows that extract tool versions from `devcontainer.json`;
* language SDK pins and infrastructure version constraints;
* package managers, bootstrap definitions, and README commands;
* sibling repositories maintained for cross-language comparison.

Update every authoritative duplicate in the same change. If values intentionally differ, document
which file owns each version rather than forcing equality.

### 9. Locking and Dependabot

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

### 10. Validate

Run cheap checks first:

1. Parse `devcontainer.json` with a JSON-with-comments-aware parser.
2. Check diagnostics and `git diff --check`.
3. Run `shellcheck` on changed lifecycle scripts when available.
4. Verify referenced scripts, Dockerfiles, Compose files, mounts, and extensions.
5. Search for stale versions in CI, docs, bootstrap files, and sibling repositories.
6. Compare `.vscode/extensions.json` recommendations with Dev Container extensions
  case-insensitively and account for every intentional exception.
7. Verify every inferred local command is available from the image, one Feature, or one lifecycle
  installer, without duplicate installation paths.
8. Confirm Dependabot covers the devcontainer directory.
9. If a lockfile is tracked, verify every configured Feature and its transitive dependency closure
  is present, with no missing, stale, or unreachable records.
10. Ask before building or rebuilding.
11. After approval, rebuild from a clean cache for image or Feature upgrades.
12. Inside the rebuilt container, print required tool versions, verify recommended extensions are
   installed in the expected extension host, and run only approved checks.

A parse alone is insufficient for an implementation. When build approval or tooling is unavailable,
report the unperformed dynamic checks rather than claiming them. An audit is complete when it reports
the static findings and clearly identifies every dynamic check not performed.

### 11. Preserve Sibling Alignment

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
10. Report versions, capability decisions, intentional exceptions, validation, and manual host setup.

## Troubleshooting

| Symptom | Response |
| --- | --- |
| Feature fails after a base upgrade | Check distribution support and Feature options first |
| Docker cannot reach the host daemon | Verify Docker-outside-of-Docker and host socket support |
| Host mount expands incorrectly | Use the correct Dev Container variable for the host platform |
| Hook works once but fails later | Move one-time work to post-create and make post-start idempotent |
| Startup changes tracked files | Remove update or generation commands from post-start |
| CI installs another tool version | Find and synchronize the authoritative version field |
| Host and container offer different extensions | Reconcile both lists and document justified exceptions |
| New file type lacks local tooling | Require execution evidence, then add one Feature or installer |
| Lockfile changes unexpectedly | Confirm the generator and repository lockfile policy |
| Files become root-owned | Restore the non-root user and use explicit `sudo` only where needed |
| Sibling repositories drift | Compare declared shared surfaces and update them together |

## References

* [Dev Container JSON reference](https://containers.dev/implementors/json_reference/)
* [Dev Container Features](https://containers.dev/features)
* [Images, Dockerfiles, and Docker Compose](https://containers.dev/guide/dockerfile)
