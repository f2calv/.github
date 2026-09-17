---
name: dependabot-management
description: 'Audit, create, align, and troubleshoot Dependabot configurations by matching supported package ecosystems to manifests, lockfiles, workflows, containers, infrastructure, and pre-commit hooks. Use when reviewing dependabot.yml, adding missing ecosystems, standardizing dependency update policy across repositories, or diagnosing missing and noisy Dependabot pull requests.'
argument-hint: '[repositories=current-workspace|path,...] [mode={audit|align|troubleshoot}]'
user-invocable: true
---

# Dependabot Management

Keep `.github/dependabot.yml` aligned with the dependencies a repository actually owns. Derive
coverage from checked-in files, preserve justified repository-specific policy, and validate every
configured directory against an updateable manifest or dependency reference.

## Scope And Safety

- Limit fleet work to explicit repositories or the active workspace folders. Never enumerate a
  parent clone directory to infer scope.
- Treat each Git repository independently, including repositories nested in a multi-root workspace.
- Exclude generated, vendored, archived, fixture, build-output, and gitignored dependency trees
  unless the repository intentionally maintains them.
- Audit before editing. Report current coverage, missing coverage, stale entries, and policy drift.
- In `audit` mode, make no changes. In `align` mode, edit only the requested repositories after the
  inventory establishes the required ecosystems and directories.
- Preserve intentional `ignore`, `allow`, registry, grouping, label, assignee, and target-branch
  rules when their rationale still applies. Do not copy a local exception across the fleet.
- Never store secret values in `dependabot.yml`. Prefer automatic `GITHUB_TOKEN` access for
  GitHub-hosted packages, supported OIDC authentication, or Dependabot secrets for private
  registries.
- Do not run builds or tests without the approval required by the repository's workflow rules.

## Ecosystem Discovery

An ecosystem is required only when a checked-in file contains dependencies that Dependabot can
update. The existence of a file extension alone is not enough.

| Evidence | Ecosystem | Directory guidance |
| --- | --- | --- |
| `.github/workflows/*.yml`, `.github/workflows/*.yaml`, root `action.yml`, or root `action.yaml` with remote `uses:` references | `github-actions` | Use `/`; local actions and workflows are not updateable dependencies |
| `.devcontainer/devcontainer.json` or another valid dev container location with Features | `devcontainers` | Use `/`; this updates Features and their lockfile, not the container image |
| `Dockerfile` or `Dockerfile.*` with tagged `FROM` images | `docker` | Include every directory containing an owned Dockerfile |
| Compose files with tagged service images | `docker-compose` | Include every directory containing an owned Compose file |
| Kubernetes manifests with tagged container images | `docker` | Include each manifest directory that the repository intentionally updates |
| `global.json` with an SDK version | `dotnet-sdk` | Include the directory containing `global.json` |
| `*.csproj`, `*.fsproj`, `*.vbproj`, `packages.config`, or `Directory.Packages.props` with package references | `nuget` | Use the common manifest root or all independent roots |
| `package.json` or npm, pnpm, or Yarn lockfiles | `npm` | Include each workspace or independent package root |
| `go.mod` | `gomod` | Include each Go module root |
| `Cargo.toml` | `cargo` | Use the Cargo workspace root or independent crate roots |
| `rust-toolchain` or `rust-toolchain.toml` with a versioned or dated channel | `rust-toolchain` | Include the containing directory |
| `.pre-commit-config.yaml` with remote hook repositories | `pre-commit` | Include the directory containing the configuration |
| `requirements*.txt`, `pyproject.toml`, `Pipfile`, or Poetry files | `pip` | Include each Python project root; use `uv` instead when uv owns resolution |
| `pyproject.toml` plus `uv.lock` managed by uv | `uv` | Include each uv project or workspace root |
| `go.work`, language lockfiles, or workspace declarations | Matching language ecosystem | Use the owning workspace root and verify nested manifests are discovered |
| Terraform `.tf` files with versioned external provider or module sources | `terraform` | Include each root or reusable child-module directory containing external dependencies |
| OpenTofu `.tf`, `.tofu`, or `terragrunt.hcl` files with external dependencies | `opentofu` | Include each root or reusable child-module directory containing external dependencies |
| Helm v3 chart directory with chart dependencies or image references | `helm` | Include each owned chart directory; Helm updates both dependencies and chart-contained images |
| `.gitmodules` | `gitsubmodule` | Use `/` when tracked submodule revisions should move automatically |

Also check the current GitHub supported-ecosystems reference for less common managers such as
Bundler, Bun, Composer, Conda, Deno, Gradle, Maven, Nix, sbt, Swift, and vcpkg. Do not guess an
ecosystem identifier from a tool name.

Determine `terraform` versus `opentofu` from the repository's owning tool and conventions, not from
the `.tf` extension alone. Do not configure both for the same files. Prefer `helm` for image
references inside Helm charts and `docker` for Dockerfiles and plain Kubernetes manifests. Do not
configure both ecosystems for the same chart directory unless duplicate updates are intentional and
verified.

## Required Workflow

### 1. Establish The Repository Set

1. Resolve repository roots from explicit paths or the active workspace folders.
2. Confirm each root with Git metadata.
3. Record whether `.github/dependabot.yml` or `.github/dependabot.yaml` exists.
4. Ignore repositories outside that set, even when they share the same parent directory.

### 2. Inventory Dependency Evidence

For each repository:

1. Search tracked files for the evidence in the ecosystem table.
2. Inspect manifests before declaring coverage. For example, an empty chart without dependencies is
   not proof that a Helm updater is useful, and a Compose file using only `build:` has no Compose
   image tag to update.
3. Identify every independent manifest root. Do not assume one root entry covers disconnected
   Terraform roots, language modules, charts, Dockerfiles, or Compose files.
4. Inspect `.gitignore` and repository conventions before including generated or local-only paths.
5. Record private dependency sources that require repository access or a configured registry.

### 3. Compare Configuration To Evidence

Classify every finding:

- `Covered`: the ecosystem and every relevant directory are configured.
- `Missing`: updateable dependency evidence has no matching update entry.
- `Partial`: the ecosystem exists but one or more independent directories are absent.
- `Stale`: a configured ecosystem or directory has no corresponding owned dependency evidence.
- `Invalid`: schema, ecosystem identifier, path, overlap, or option usage is invalid.
- `Policy drift`: schedules, grouping, limits, or commit-message conventions differ without a
  repository-specific reason.
- `Intentional exception`: a documented, current constraint requires local policy.

Produce the matrix before editing. For fleet reviews, include one row per repository and list exact
ecosystem-directory pairs for every gap.

### 4. Align The Configuration

Use this baseline unless repository-specific instructions establish another policy:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly

  - package-ecosystem: pre-commit
    directory: /
    schedule:
      interval: weekly
```

Apply these rules:

- Add one update entry for every supported ecosystem with updateable dependency evidence.
- Use `directory` for one manifest root. Use `directories` for multiple roots and globs. Paths are
  repository-relative, begin with `/`, and must not overlap another entry for the same ecosystem and
  target branch.
- Prefer a single `directories` entry when the ecosystem shares the same schedule and policy. Use
  separate entries only when roots need different registries, schedules, groups, or other behavior.
- Keep the fleet's established schedule when it is valid. If setting `time`, quote `hh:mm`; add an
  IANA `timezone` when local time is intended. Otherwise the time is UTC.
- Use `groups` for dependencies that must move together or to reduce proven pull-request noise.
  Consider `group-by: dependency-name` for the same dependency across multiple directories.
- Use `multi-ecosystem-groups` only when components across ecosystems are released and validated
  together. Do not group unrelated updates merely to reduce pull-request count.
- Set `open-pull-requests-limit` deliberately. Its default is five version-update pull requests per
  ecosystem; security updates have a separate, unlimited queue.
- Prefer `cooldown` over permanent ignores when the goal is to wait for release maturity.
- Add `ignore` rules only for a verified incompatibility or deliberate support boundary. Scope them
  to the narrowest dependency and update type, and add a short rationale comment.
- Preserve the default branch unless the repository explicitly maintains dependencies on another
  branch. When `target-branch` is set, that entry applies only to version updates on the named
  branch; its options no longer apply to security updates, which always target the default branch.
- Configure private registries with top-level `registries` and per-update references. Use
  automatic `GITHUB_TOKEN` access for GitHub-hosted packages, supported OIDC authentication, or
  `${{secrets.NAME}}`; never store a token, password, private key, or derived authorization value.
  Use `helm-registry` only for HTTP Basic Auth to non-OCI chart repositories and `docker-registry`
  for OCI-compliant Helm registries.
- Keep YAML at two-space indentation and retain the repository's established ordering where it is
  coherent.

### 5. Verify

1. Parse the YAML with the repository's existing YAML tooling.
2. Confirm `version: 2`, a non-empty `updates` list, required keys, supported ecosystem identifiers,
  valid schedules, and unique non-overlapping paths between entries for each ecosystem and target
  branch. Different ecosystems may validly use the same directory.
3. Re-run manifest discovery and prove every updateable ecosystem-directory pair is covered.
4. Prove every literal directory exists and every `directories` glob matches at least one relevant
  manifest root containing updateable dependency evidence.
5. Run the repository's configured lint or pre-commit check only after obtaining any approval its
   workflow rules require.
6. Review the diff for lost local policy, credentials, private identifiers, unrelated formatting,
   and accidental edits outside the requested repositories.
7. After merge, use the repository's Dependabot update logs to verify GitHub accepted the
   configuration and can resolve each ecosystem. Local YAML parsing cannot validate registry access
   or Dependabot's resolver behavior.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No pull request appears | Update logs, schedule, open PR limit, cooldown, ignored versions, and whether the dependency is already allowed by its manifest range |
| Manifest not found | The configured path, independent root boundaries, generated-file exclusions, and whether `directory` should be `directories` |
| Duplicate pull requests | Overlapping entries, multiple target branches, or a dependency represented in Docker, Compose, Helm, and infrastructure files |
| Private dependency fails | Dependabot repository access, registry type, per-update registry reference, secret name, and source URL |
| Pre-commit SHA moves unexpectedly | Inspect the same-line `# frozen: <version-or-prefix>` comment; a bare SHA follows the upstream default-branch HEAD |
| Dev container image stays stale | Add the matching `docker` entry; `devcontainers` updates Features, not the image |
| .NET SDK stays stale | Add `dotnet-sdk` for `global.json`; `nuget` updates packages, not the SDK |
| Compose image stays stale | Add `docker-compose`; a `docker` entry for a Dockerfile does not cover Compose service images |
| Terraform root is skipped | Add its independently initialized directory or a non-overlapping `directories` glob |
| Helm update is incomplete | Check chart dependencies, image references, registry type, lockfile changes, and repository-specific chart validation |
| Configuration is accepted but noisy | Add evidence-based groups, cooldowns, or limits; do not suppress security updates to hide volume |

## Reporting

Report:

- repositories audited and the scope source;
- ecosystems and directories detected, configured, added, removed, or retained;
- stale or invalid entries;
- intentional exceptions and their rationale;
- registry or resolver issues that local validation cannot prove;
- validation performed and any checks not run.

Keep reports from public repositories free of private repository names, coordinates, paths,
infrastructure details, and credentials.

## References

- [Dependabot options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference)
- [Dependabot supported ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories)
