# ADR 0001: Skill Library Distribution

**Status:** Accepted.
**Date:** 2026-10-31.
**Scope:** Independent versioning of each skill in `.github/skills/`, packaging as Spec Kit
extensions in GitHub Releases, and installation through one bootstrap extension.

## Context and Problem

Skills are consumed natively by adding this repository to a workspace or linking its folders into the
user profile. That route stays supported. Consumers who want selected skills, at exact versions, in
a Spec Kit repository need versioned packages and a way to install a skill with the skills it needs.

The first implementation (tags `1.5.0` to `1.5.3`) grew to roughly 10,000 lines of PowerShell,
Python and tests, plus Spec Kit dogfooding artifacts. Most of it defended against hostile writers,
crashes and concurrency that a single-owner Markdown packager does not face, and it reimplemented
installation that Spec Kit already provides. It never published a release. Git history keeps it.

## Decision

1. **One sidecar per skill.** Every skill folder has `skill.metadata.yaml` with `version`, optional
   `facets`, `required` skills pinned to exact versions, `related` skills with a reason, and
   `externalFiles` outside the folder. The component ID is the folder name.
2. **PowerShell and `yq` only.** Repository tooling uses PowerShell 7.4+, Git and `yq` v4. No Python.
3. **One extension per skill.** A build packages the skill folder, its external files and `LICENSE`
   into a deterministic Spec Kit extension ZIP. Required skills are separate extensions, not bundled.
4. **Versions are checked, not inferred.** A pull request fails when a skill changed since its last
   `<id>/X.Y.Z` tag without a version bump, or when a required pin is stale. `Set-SkillVersion`
   bumps a skill and cascades pin updates and patch bumps to skills that require it.
5. **Releases on merge.** On `main`, each component without a matching tag is built and published
   as GitHub Release `<id>/X.Y.Z`. A rolling `skills-catalog` release holds one Spec Kit catalog
   with every published version. GitHub Pages may replace the rolling release after the demo.
6. **One bootstrap command.** The `skill` extension provides `/speckit-skill-library`. Its
   PowerShell helper wraps the `specify` CLI: it searches the catalog, resolves the required
   closure, offers related skills for explicit selection, installs through `specify extension add`
   and lists installed guidance for loading. Spec Kit verifies archive digests.

## Options Considered

| Option | Assessment |
| --- | --- |
| Keep the first implementation | Rejected: too large to maintain or demo, and it never published. |
| Bundle required skills into each ZIP | Rejected: duplicates content; the bootstrap resolves the closure instead. |
| Rely on Spec Kit dependency resolution | Unavailable: Spec Kit 1.2.3 only checks `requires.speckit_version`. |
| Native consumption only | Kept as the default route, but it offers no versioned selection. |

## Consequences

- Consumers need the `specify` CLI, PowerShell 7.4+ and network access to GitHub Releases.
- Installing a skill through `specify extension add` directly skips its required skills; use the
  bootstrap command.
- Related skills install at their current catalog version; only required edges pin versions.
- Renaming a skill folder creates a new component ID. Published releases and tags are never moved.
- Digests prove integrity, not authorship. Signing, upgrades of installed skills and uninstall
  orchestration are out of scope until needed.

## Validation and Delivery

- [x] Accept this minimal decision and delete the previous design record's history narrative.
- [x] Delete the first implementation, its tests, delivery workflows and Spec Kit dogfooding folders.
- [x] Add a sidecar to every skill and validate all sidecars with `yq` and PowerShell.
- [x] Build a deterministic extension ZIP per skill with external files and `LICENSE`.
- [x] Fail pull requests on unbumped changes or stale required pins; bump with cascade.
- [x] Build the `skill` bootstrap extension with `/speckit-skill-library`.
- [x] Publish missing `<id>/X.Y.Z` releases from `main`: 46 skills and `skill` at `1.0.0` (PR #37).
- [x] Publish the rolling `skills-catalog` release (PR #38, after fetching remote-only tags).
- [x] Cover validation, build, version checks, bump cascade and plan resolution with Pester.
- [x] Rewrite the `skill-library` skill and README for the new workflow.
- [x] Install and load skills with related selection in a fresh consumer from a local catalog.
- [x] Install and load skills from the published catalog in a fresh Linux consumer.
- [ ] Repeat the published-catalog install and editor `load` on a Windows host.
- [x] Publish a real follow-on version: `skill-library/1.0.1` after the PR gate flagged its change.
- [ ] Publish a follow-on version of a skill with required dependents and observe the pin cascade.

## Handover

Update this section at the end of every session, on any environment, and remove entries once
they no longer apply. The checklist above is the source of truth for what remains open.

**State on 2026-10-31.** [PR #37](https://github.com/f2calv/.github/pull/37) merged the slim
workflow and published 47 releases at `1.0.0`. Its catalog step failed because `gh release create`
makes tags on GitHub only and the job read them before fetching.
[PR #38](https://github.com/f2calv/.github/pull/38) fixed that, and its merge published
`skill-library/1.0.1` and the `skills-catalog` release listing 47 skills with version history.
[PR #39](https://github.com/f2calv/.github/pull/39) recorded that state here (tag `1.6.2`).
From the Dev Container, a fresh `specify init --script ps` consumer installed `skill` from the
published catalog, then `install docs-adr -Related github-issues-and-pull-requests` installed
`repository-privacy`, `docs-adr` and the related skill from GitHub Releases; `list` and `load` worked.

**Windows host check (2026-10-31).** PowerShell 7.6, Git, GitHub CLI and `yq` v4 are present;
`uv` and the Specify CLI are not. Spec Kit's PowerShell is only the project scripts that
`specify init --script ps` copies into `.specify/scripts/powershell/`. The `specify` CLI itself,
which provides `init` and `extension add`, is Python only, and its releases include no
standalone executable. Where `uv` is unavailable, install it with pip into a virtual environment
using the host's configured package index: `python -m venv ~/.venvs/specify`, then
`~/.venvs/specify/Scripts/python -m pip install specify-cli==1.2.3` on Windows
(`bin/python` on Linux or macOS). The end-to-end consumer run on Windows has not started.

**Next session, part 1: pin cascade (Dev Container).** `repository-privacy` is the only skill that
`docs-adr` requires; `terraform-infrastructure` lists it as related only.

1. Make a real change to `repository-privacy`, then run `git fetch --tags` and
   `./.github/skills/skill-library/scripts/Set-SkillVersion.ps1 -Id repository-privacy`.
2. Expect `repository-privacy` at `1.0.1`, and `docs-adr` patch-bumped past its latest tag with its
   required pin updated. `terraform-infrastructure` must not change. Run `Test-SkillLibrary.ps1`.
3. Merge, then confirm both new releases and their versions in the `skills-catalog` catalog. Tick
   the pin-cascade box.

**Next session, part 2: Windows consumer.** Install PowerShell 7.4+, Git, GitHub CLI, `yq` v4
(`winget install MikeFarah.yq`) and the Specify CLI
(`uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v1.2.3`, or the pip
route above). Then:

1. Confirm the catalog resolves:
   `https://github.com/f2calv/.github/releases/download/skills-catalog/catalog.json`.
2. In a fresh demo repository, follow
   [Install in a Consumer](../.github/skills/skill-library/SKILL.md#install-in-a-consumer).
3. Run `/speckit-skill-library install docs-adr` in Copilot Chat: expect `repository-privacy` as
   required and an offer of `github-issues-and-pull-requests`. Then `load docs-adr`, ask a question
   using it, and tick the Windows box.

**Known gaps.** The repository's Pester fixtures use `chmod` and shebang fake commands, so run the
repository tests in CI or on Linux, not on a Windows host. The consumer helper has no such limit.

**Skill branches started before PR #37.** Any such branch, on any environment, needs `main` merged
in, then `git fetch --tags`, `New-SkillMetadata.ps1`, `Set-SkillVersion.ps1` and
`Test-SkillLibrary.ps1` as described in the
[skill guide](../.github/skills/skill-library/SKILL.md#validate-and-bump). The PR gate fails with
the script to run for any missing sidecar or unbumped change. None remain in the Dev Container clone.

**Unmerged branches.** `f2calv/2026-10-updates11` carries this handover update, three PowerShell
lessons in `shell.powershell.instructions.md`, and `docs-adr/1.0.1`, which makes ADRs living
documents with an optional handover section. It is not yet pushed. Push it and open a PR before
starting the next session's work, then delete this entry.

## Open Questions

- Should the catalog move to GitHub Pages after the demo?
- Is `specify extension` enough for upgrading or removing installed skills, or does the bootstrap
  need its own support? See Consequences for the current scope.
