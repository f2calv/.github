---
name: pre-commit-management
description: 'Audit, add, align, update, run, and troubleshoot pre-commit across one repository or an explicit multi-root workspace. Use when managing .pre-commit-config.yaml, updating hook revisions or the pre-commit runtime, adding CI lint gates or Dependabot coverage, installing an opt-in pre-push hook, or running hooks without local Python through the bundled Docker fallback.'
argument-hint: '[repositories=current-workspace|path,...] [mode={audit|align|update|run|install-pre-push|troubleshoot}] [files=...]'
user-invocable: true
compatibility: 'Native execution requires pre-commit 4.6.2 and Git. The fallback requires Docker. Fleet auditing requires PowerShell 7.4 and Git.'
---

# Pre-commit Management

Manage pre-commit as one repository-wide lint contract: root configuration, hook revisions,
Dependabot updates, local execution, and the required CI lint job. Prefer the repository's own
configuration and preserve justified exclusions rather than replacing every file with a generic
template.

## Scope And Safety

- Resolve repositories from explicit paths or active workspace folders. Never enumerate a parent
  clone directory to infer scope.
- Treat every Git repository independently, including repositories in a multi-root workspace.
- Audit before editing. Record configuration, hooks, revisions, exclusions, CI, Dependabot, runtime
  pins, devcontainer tooling, and documentation.
- Preserve repository-specific `exclude`, hook arguments, local hooks, stages, language versions,
  and generated-file policy unless evidence shows they are stale.
- Never install a per-commit hook automatically. `install-pre-push` is an explicit user operation.
- Never run `pre-commit autoupdate` from a devcontainer lifecycle script or other automatic startup
  path. Dependabot owns routine hook updates; this skill handles deliberate fleet updates.
- Hooks may modify files. After every run, inspect `git status`, review the diff, and rerun the same
  command once when a formatter changed files.
- Follow repository visibility, privacy-scan, build/test approval, branch, commit, and push rules.

## Fleet Contract

Every repository must have:

1. `.pre-commit-config.yaml` at the repository root.
2. `default_install_hook_types: [pre-push]` so an explicit install creates the cheaper pre-push
   gate, never a per-commit gate.
3. A `.github/workflows/ci.yml` `lint` job that runs on pull requests and default-branch pushes.
4. Release fan-in that depends on `lint` when the repository creates releases.
5. A root Dependabot `pre-commit` ecosystem entry so hook revisions remain current.

Use the account-level [baseline configuration](../../../.pre-commit-config.yaml) as the nearest
shared precedent. Preserve local exclusions and hooks while aligning common hook sources and
arguments.

## Current Shared Versions

Resolve latest versions live before changing these values. At the time this skill was last updated:

| Component | Version | Authority |
| --- | --- | --- |
| pre-commit runtime | `4.6.2` | PyPI `pre-commit` latest release |
| `pre-commit/pre-commit-hooks` | `v6.0.0` | GitHub latest release |
| `bmares/check-json5` | `v1.0.1` | GitLab latest stable tag |
| `igorshubovych/markdownlint-cli` | `v0.49.1` | GitHub latest release |

The runtime pin must match the shared lint workflow and the bundled Docker fallback. Hook revisions
live in each repository configuration and are normally maintained by Dependabot.

## Required Workflow

### 1. Establish The Repository Set

1. Resolve explicit roots from the request or active workspace.
2. Verify each root with Git metadata.
3. Run the fleet audit:

   ```powershell
   pwsh ./.github/skills/pre-commit-management/scripts/Test-PreCommitFleet.ps1 `
     -RepositoryPath <repo1>,<repo2>
   ```

4. Classify missing files, CI drift, release-gate drift, Dependabot drift, version drift, and
   intentional local exceptions before editing.

### 2. Resolve Latest Versions

- Resolve the runtime from `https://pypi.org/pypi/pre-commit/json`.
- Resolve GitHub-hosted hooks from their latest release or stable tag.
- Resolve GitLab-hosted hooks from stable tags.
- Use `pre-commit autoupdate` only as evidence and review every resulting revision. It does not own
  runtime, CI, Dependabot, or Docker fallback versions.
- Reject prereleases unless the repository explicitly tests and requires one.

### 3. Align Repository Configuration

1. Add a missing root `.pre-commit-config.yaml` from the account baseline.
2. Merge rather than overwrite repository-specific exclusions and hooks.
3. Keep common hook revisions and arguments aligned across repositories.
4. Add or repair the Dependabot `pre-commit` ecosystem at `/`.
5. Add or repair the CI `lint` job and include it in release fan-in.
6. Remove automatic lifecycle-script updates; startup must never mutate tracked hook pins.

### 4. Run Or Update Hooks

Use the bundled entry point from the central repository:

```powershell
# Run every hook against every tracked file. Native pre-commit is preferred.
pwsh ./.github/skills/pre-commit-management/scripts/Invoke-PreCommit.ps1 `
  -RepoRoot <repository>

# Run one hook or selected files.
pwsh ./.github/skills/pre-commit-management/scripts/Invoke-PreCommit.ps1 `
  -RepoRoot <repository> -HookId markdownlint -Files README.md,docs/example.md

# Deliberately update hook revisions.
pwsh ./.github/skills/pre-commit-management/scripts/Invoke-PreCommit.ps1 `
  -RepoRoot <repository> -Mode Update

# Force the pinned Docker fallback even when native pre-commit is available.
pwsh ./.github/skills/pre-commit-management/scripts/Invoke-PreCommit.ps1 `
  -RepoRoot <repository> -ForceDocker

# Explicit opt-in only; never invoke this automatically.
pwsh ./.github/skills/pre-commit-management/scripts/Invoke-PreCommit.ps1 `
  -RepoRoot <repository> -Mode InstallPrePush
```

The script prefers an existing `pre-commit` executable or installed Python module. When neither is
available it builds and launches `pre-commit-runner:4.6.2`, containing Python 3.12, Node 22, Git,
and pre-commit 4.6.2. A named cache volume preserves hook environments between runs.

### 5. Verify

1. Parse every YAML configuration and workflow.
2. Run `Test-PreCommitFleet.ps1` again and require every repository to pass.
3. Run hooks against all files in every changed repository.
4. Review formatter changes and rerun once when needed.
5. Confirm the CI lint job and release dependency from the actual workflow structure.
6. Run the Pester suite after changing bundled scripts:

   ```powershell
   pwsh ./.github/skills/pre-commit-management/scripts/Invoke-Tests.ps1
   ```

7. Review diffs for lost local exclusions, vendored/generated churn, credentials, identifiers, and
   changes outside the explicit repository set.

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| `pre-commit` is unavailable | Use `Invoke-PreCommit.ps1`; it falls back to Docker automatically |
| Markdown hook reports an unsupported Node engine | Rebuild the bundled image; it includes Node 22 |
| Docker reports unsafe repository ownership | Use the bundled entrypoint, which configures `/src` as a safe directory |
| First Docker run is slow | Keep the named cache volume; hook environments are reused afterwards |
| Hook changes files and exits 1 | Review the diff, then rerun the same command once |
| A direct linter disagrees with CI | Run pre-commit from the repository root so config arguments and exclusions apply |
| `autoupdate` changes a justified frozen revision | Restore the intentional pin and document its constraint beside the revision |
| CI passes but release bypasses lint | Add `lint` to the release job's `needs` fan-in |
| PyPI download fails with TLS errors | Use the Docker fallback only if its image can build; otherwise report the network blocker |

## Reporting

Report:

- repositories audited and the source of scope;
- missing or repaired config, CI, release-gate, and Dependabot coverage;
- runtime and hook revisions before and after;
- repository-specific exclusions and hooks preserved;
- native or Docker execution mode;
- hook results and formatter-modified files;
- validation not run and why.

Keep public reports free of private repository names, paths, topology, identifiers, and credentials.
