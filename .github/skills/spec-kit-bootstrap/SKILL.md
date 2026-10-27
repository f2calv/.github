---
name: spec-kit-bootstrap
description: 'Bootstrap a new or existing repository with GitHub Spec Kit and the Specify CLI for spec-driven development. Use when adopting spec-kit, initializing .specify, or preparing a Dev Container to run specify commands; delegates container setup to the containers-devcontainer skill.'
---

# Spec Kit Bootstrap

Add Spec Kit's project scaffolding and a reproducible development environment, then hand off to
the first bounded feature. Do not retroactively specify an entire existing application or start
implementation merely because bootstrap was requested.

## Quick Start

```text
/spec-kit-bootstrap add Spec Kit to this repository
/spec-kit-bootstrap bootstrap a new repository with Copilot and a Dev Container
```

## 1. Establish the Baseline

1. Resolve the target repository, read its instructions and `.editorconfig`, and inspect the
   current branch and working-tree changes. Preserve existing work.
2. Look for `.specify/`, generated agent skills or prompts, an existing constitution, and
   `.devcontainer/`. If Spec Kit is already initialized, identify the missing setup rather than
   rerunning initialization over customized files; use the upstream upgrade guide for upgrades.
3. Default to GitHub Copilot unless the caller names another integration. Confirm any unresolved
   target path or agent choice. Creating a remote repository is separate from local initialization;
   use the `repository-baseline` skill when remote creation is requested.
4. Check the official installation guide and a published release before choosing the CLI version.
   Record an exact version in the container's installation source, not a floating Git branch.
   Verify that release's `specify init --help`; flags and generated command formats have changed.

## 2. Prepare the Dev Container

Invoke the [Dev Container skill](../containers-devcontainer/SKILL.md) in `add` or `reconcile` mode. It owns
image and Feature selection, lifecycle scripts, extension parity, lockfiles, Dependabot, and
build approval. Preserve the repository's application toolchain; do not replace it with a
Python-only image just to run Spec Kit.

Required capabilities:

* Python 3.11+ (or the selected release's higher minimum), `uv`, and Git.
* The `specify` executable installed once for the non-root development user, with its tool-bin
  directory on `PATH` in both terminals and the agent's execution environment.
* The chosen helper runtime: default to `--script sh` in a Linux container; use `ps` when the
  repository intentionally uses PowerShell and `py` when Python helpers are preferred. Include
  that runtime explicitly rather than inheriting the Windows host's default.
* Copilot available in the selected VS Code harness. Do not install an unrelated agent CLI or
  mount credentials just to satisfy a tool-presence check.

Use an exact published `specify-cli` version with `uv tool install`, or the official source-install
form pinned to a release tag. Verify availability before writing the pin. Let `uv` manage its
isolated tool environment; do not create a repository virtual environment or add Spec Kit to the
application's dependencies. Install through one image/Feature/lifecycle owner and never initialize
the repository from a container lifecycle hook.

The reusable [Specify installer](./scripts/Install-Specify.ps1) accepts an exact release version,
adds the non-root user's tool-bin directory to `PATH`, and verifies `specify version`. Compose it
with the generic Dev Container tool verifier from a thin repository lifecycle entry point only
when this repository needs Spec Kit; generic container initialization must not install it.

After an approved build or rebuild, run inside the container:

```text
python --version
uv --version
git --version
specify version
specify init --help
```

Confirm the reported CLI version matches the pin and the selected helper shell is available.
If rebuilding is declined or unavailable, report runtime validation as outstanding.

## 3. Initialize Deliberately

Run from the target repository root inside the container. For a fresh, empty target, the current
Copilot/Linux setup is:

```text
specify init --here --integration copilot --script sh --non-interactive
```

For a non-empty repository, inspect potentially conflicting generated paths first, obtain explicit
approval for the merge, and only then add `--force`. That flag can replace managed files; it is not
a harmless non-interactive switch. Do not stash, commit, reset, or overwrite existing work
automatically. Stop for a preservation decision if customized generated files would be replaced.

Use `--ignore-agent-tools` only when the agent runs through the editor or elsewhere and the CLI's
executable check is inapplicable; it does not verify editor discovery. Do not add optional
extensions, presets, workflows, or the Git extension during basic bootstrap. Keep existing branch
naming and commit/push authorization unchanged.

Review the generated diff: expect `.specify/` and integration-specific skills or prompts, not
application rewrites. Preserve the central-instructions pointer and repository-specific guidance;
do not copy central skills into the target or let generated context replace existing instructions.
Keep Spec Kit's required artifact layout rather than moving its files into `docs/`.

## 4. Verify and Hand Off

1. Inspect generated files for unresolved placeholders, conflicting instructions, and accidental
   secrets. Check local links and `git diff --check`; use the repository's existing lint workflow.
2. Open the target in the intended container and Copilot harness, reload customization discovery
   if necessary, and verify that the generated Spec Kit commands are available. File existence
   alone does not prove discovery.
3. Explain the small workflow below. These are **chat commands**, not terminal commands. Current
   Copilot skills use `/speckit-*`; older prompt integrations use `/speckit.*`. Use the names
   actually generated by the selected release and integration.
4. Create or refine the constitution only with agreed project principles, grounded in existing
   instructions and architecture. Do not invent standards or duplicate the shared rules.
5. For an existing application, choose the next bounded change and preserve existing behavior.
   Ask before proceeding beyond bootstrap; tests and implementation need their normal approval.

| Step | Purpose |
| --- | --- |
| `/speckit-constitution` | Establish project principles once |
| `/speckit-specify` | Describe the feature's what and why |
| `/speckit-clarify` | Resolve important ambiguities before planning |
| `/speckit-plan` | Design within the existing architecture and toolchain |
| `/speckit-tasks` | Produce actionable implementation tasks |
| `/speckit-analyze` | Check consistency before implementation |
| `/speckit-implement`, then `/speckit-converge` | Implement and assess remaining gaps when authorized |

Report the CLI pin, helper runtime, generated paths, container changes, validation performed,
any unverified runtime/discovery checks, and the suggested first chat command. Update the target's
developer setup documentation with its pinned installation and container usage, not a second
Spec Kit tutorial.

## References

* [Official Spec Kit repository](https://github.com/github/spec-kit)
* [Installation and version pinning](https://github.github.io/spec-kit/installation.html)
* [Existing-project adoption](https://github.github.io/spec-kit/guides/existing-projects.html)
* [Spec-driven development walkthrough](https://github.github.io/spec-kit/quickstart.html)
* [Upgrading an existing installation](https://github.github.io/spec-kit/upgrade.html)

## Maintaining This Skill

* Recheck Python requirements, official installation channels, version reporting and init flags
  against the selected release; do not assume examples on the default branch match older pins.
* Track generated Copilot locations, slash-command naming, helper-runtime choices, and overwrite
  behavior when upstream changes its templates or integration model.
* Keep container integration delegated to the containers-devcontainer skill; add deeper adoption guidance
  only when actual repository use demonstrates a missing step.
