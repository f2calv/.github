---
name: devcontainer
description: 'Create, update, align, and validate Dev Container configurations. Use when adding .devcontainer/devcontainer.json, upgrading images or Features, changing tool versions, lifecycle scripts, mounts, extensions, or lockfiles, and synchronizing Dependabot, CI, documentation, and sibling repositories.'
argument-hint: 'mode={add|update|upgrade|audit|align} [scope=repository-or-workspace]'
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
/devcontainer align the sibling repositories
/devcontainer audit this workspace for drift
```

| Mode | Contract |
| --- | --- |
| `add` | Create the smallest useful configuration and synchronize its consumers |
| `update` | Preserve the current model while applying the requested changes |
| `upgrade` | Check releases, compatibility, lock data, and version consumers |
| `audit` | Make no edits; report findings and any dynamic checks not performed |
| `align` | Change only the explicitly declared repository set |

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

### 4. Handle Mounts and Credentials

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

### 5. Design Lifecycle Scripts

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

### 6. Synchronize Consumers

Before changing an image, Feature, option, or tool version, search for its old value and key.

Common consumers are:

* Actions or workflows that extract tool versions from `devcontainer.json`;
* language SDK pins and infrastructure version constraints;
* package managers, bootstrap definitions, and README commands;
* sibling repositories maintained for cross-language comparison.

Update every authoritative duplicate in the same change. If values intentionally differ, document
which file owns each version rather than forcing equality.

### 7. Locking and Dependabot

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

### 8. Validate

Run cheap checks first:

1. Parse `devcontainer.json` with a JSON-with-comments-aware parser.
2. Check diagnostics and `git diff --check`.
3. Run `shellcheck` on changed lifecycle scripts when available.
4. Verify referenced scripts, Dockerfiles, Compose files, mounts, and extensions.
5. Search for stale versions in CI, docs, bootstrap files, and sibling repositories.
6. Confirm Dependabot covers the devcontainer directory.
7. If a lockfile is tracked, verify every configured Feature and its transitive dependency closure
  is present, with no missing, stale, or unreachable records.
8. Ask before building or rebuilding.
9. After approval, rebuild from a clean cache for image or Feature upgrades.
10. Inside the rebuilt container, print required tool versions and run only approved checks.

A parse alone is insufficient for an implementation. When build approval or tooling is unavailable,
report the unperformed dynamic checks rather than claiming them. An audit is complete when it reports
the static findings and clearly identifies every dynamic check not performed.

### 9. Preserve Sibling Alignment

When repositories intentionally mirror each other:

* Compare image families, Feature sets, lifecycle responsibilities, mounts, and common extensions.
* Keep shared lifecycle scripts byte-identical where required.
* Isolate language-specific deviations in clearly marked sections.
* Apply and validate the change across the entire declared sibling set.
* Commit per repository when histories are separate.

## Upgrade Procedure

1. Inventory the image, Features, options, lockfile, Dependabot, and version consumers.
2. Read official release notes and confirm base-distribution compatibility.
3. Change the smallest authoritative set of fields.
4. Regenerate tracked lock data rather than editing it.
5. Synchronize CI, documentation, and siblings.
6. Run parse, lint, reference, and diff checks.
7. Ask before rebuilding.
8. Rebuild and verify tool versions after approval.
9. Report versions, compatibility decisions, validation, and manual host setup.

## Troubleshooting

| Symptom | Response |
| --- | --- |
| Feature fails after a base upgrade | Check distribution support and Feature options first |
| Docker cannot reach the host daemon | Verify Docker-outside-of-Docker and host socket support |
| Host mount expands incorrectly | Use the correct Dev Container variable for the host platform |
| Hook works once but fails later | Move one-time work to post-create and make post-start idempotent |
| Startup changes tracked files | Remove update or generation commands from post-start |
| CI installs another tool version | Find and synchronize the authoritative version field |
| Lockfile changes unexpectedly | Confirm the generator and repository lockfile policy |
| Files become root-owned | Restore the non-root user and use explicit `sudo` only where needed |
| Sibling repositories drift | Compare declared shared surfaces and update them together |

## References

* [Dev Container JSON reference](https://containers.dev/implementors/json_reference/)
* [Dev Container Features](https://containers.dev/features)
* [Images, Dockerfiles, and Docker Compose](https://containers.dev/guide/dockerfile)
