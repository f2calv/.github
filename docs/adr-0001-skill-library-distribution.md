# ADR 0001: Skill Library Distribution

**Status:** Accepted.
**Date:** 2026-11-01.
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
2. **PowerShell and `yq` for maintainer tooling.** Repository tooling that validates, versions, builds
   and publishes skills uses PowerShell 7.4+, Git and `yq` v4 only. The consumer helper in decision
   8 is the one exception.
3. **One extension per skill.** A build packages the skill folder, its external files and `LICENSE`
   into a deterministic Spec Kit extension ZIP. Required skills are separate extensions, not bundled.
   [ADR 0002](adr-0002-agent-plugins-packaging.md) adds an Agent Plugins ZIP to the same release.
4. **Versions are checked, not inferred.** A pull request fails when a skill changed since its last
   `<id>/X.Y.Z` tag without a version bump, when its version is more than one patch, minor or major
   step past that tag, or when a required pin is stale. `Set-SkillVersion` bumps from the last tag,
   so a skill is bumped at most once per branch, and cascades pin updates and patch bumps to skills
   that require it. Unreleased skills are never bumped; their first release uses the authored version.
5. **Releases on merge.** On `main`, each component without a matching tag is built and published
   as GitHub Release `<id>/X.Y.Z`. CI then regenerates one Spec Kit `catalog.json` with every
   published version, plus an `index.html` listing the skills, and deploys both to GitHub Pages.
6. **One bootstrap command.** The `skill` extension provides `/speckit-skill-library`. Its
   helper wraps the `specify` CLI: it searches the catalog, resolves the required
   closure, offers related skills for explicit selection, installs through `specify extension add`,
   upgrades every installed skill to its latest version with `upgrade-all` and lists installed
   guidance for loading. Spec Kit verifies archive digests.
7. **Copy installed guidance where Copilot discovers it.** After every install, upgrade, removal or
   prune, the bootstrap mirrors each enabled skill's `resources/.github/` into the workspace
   `.github/`, so `.github/skills/<id>/` and `.github/instructions/` load natively in new chats. It
   records each copied file's SHA-256, owning skills and version in `.skill-library.json`. A copy is
   replaced or deleted only while its bytes still match that record; a modified copy, or a file the
   bootstrap did not write, is kept and reported, so removing a skill never discards local edits.
8. **Portable helper in three languages.** The bootstrap ships the helper as PowerShell
   (`Invoke-SkillLibrary.ps1`), Bash (`bash/skill-library.sh`) and Python
   (`python/skill_library.py`). The command declares all three in its front-matter `scripts` map
   (`ps`, `sh`, `py`), and Spec Kit substitutes `{SCRIPT}` with the variant chosen at
   `specify init --script`, falling back by platform. Each variant is a full implementation with the
   same commands, arguments, output and `.skill-library.json` state, so a workspace can switch
   variant at any time. One set of scenarios, run by Pester, pytest and bats-core against shared
   catalog fixtures, keeps them in parity. The Bash variant needs Bash 4+, `jq`, `curl` and
   `sha256sum` or `shasum`; the Python variant uses the standard library only, under the
   interpreter Spec Kit already requires.

### Discovery Gap

Spec Kit 1.2.3 extensions provide `commands`, `hooks`, `scripts`, `templates` and `config`; there is
no skill type. The Copilot integration writes only commands into `.github/skills/speckit-<command>/`.
Each skill package declares its `SKILL.md` as a template, which Spec Kit records but Copilot never
reads, so a skill installed only as an extension under `.specify/extensions/<id>/resources/` is not
discovered: its description never reaches the agent and its instructions never apply by `applyTo`.
It was usable only through an explicit `load` in the current chat. The `extension.yml` description
serves the catalog, `specify extension list` and `search`, not Copilot discovery.

## Options Considered

| Option | Assessment |
| --- | --- |
| Keep the first implementation | Rejected: too large to maintain or demo, and it never published. |
| Bundle required skills into each ZIP | Rejected: duplicates content; the bootstrap resolves the closure instead. |
| Rely on Spec Kit dependency resolution | Unavailable: Spec Kit 1.2.3 only checks `requires.speckit_version`. |
| Native consumption only | Kept as the default route, but it offers no versioned selection. |
| Catalog on a rolling release asset | Replaced: each publish clobbered a release asset and the URL depended on a release. Pages deploys atomically and hosts a browsable index. |
| Discovery: rely on `load` only | Rejected: guidance applies only in the chat that loaded it, and instructions never apply by `applyTo`. |
| Discovery: declare each skill as a Spec Kit command | Rejected: renames it `speckit-<id>` and copies only the one file, breaking links to its references and instructions. |
| Discovery: point editor settings at extension folders | Rejected: editor-specific and needs a setting per installed skill. |
| Discovery: symlink instead of copy | Rejected: a link has no install-time content to audit, and symlinks are unreliable on Windows checkouts. |
| Discovery: copy with recorded SHA-256 | Chosen: native discovery in any client that reads `.github/`, plus an audit record that protects local edits on upgrade and removal. |
| Helper: PowerShell only | Replaced: consumers who chose `specify init --script sh` would need PowerShell installed just for the bootstrap. |
| Helper: Python core with thin `ps` and `sh` launchers | Rejected: one implementation, but every variant would then depend on a Python interpreter and the launchers add a second hop to debug. |
| Helper: three full implementations | Chosen: each variant runs natively in the shell Spec Kit selected; shared scenarios and fixtures make divergence a test failure. |
| Helper: Bash reads JSON with Python | Rejected: `jq` is the common, small JSON tool for shell scripts and keeps the Bash variant independent of Python. |
| Maintainer tooling in three languages | Rejected: CI runs it in one controlled environment, so PowerShell alone suffices. |

## Consequences

- Consumers need the `specify` CLI, network access to GitHub Pages and Releases, and the runtime of
  their helper variant: PowerShell 7.4+, Bash 4+ with `jq`, `curl` and a SHA-256 tool, or the Python
  that Spec Kit already uses. macOS ships Bash 3.2, so macOS consumers choose `ps` or `py`, or install
  a newer Bash.
- Every helper change is made three times. A scenario added to one test suite must be added to the
  other two; the shared fixtures fail all three suites when the catalog format drifts.
- Installing a skill through `specify extension add` directly skips its required skills; use the
  bootstrap command.
- Related skills install at their current catalog version; only required edges pin versions.
- Renaming a skill folder creates a new component ID. Published releases and tags are never moved.
- Digests prove integrity, not authorship. Signing is out of scope until needed. The bootstrap
  records whether each skill was chosen or only required, so `prune` removes required skills no
  chosen skill needs, and `remove` removes a chosen skill that no other installed skill requires.
- Copies under `.github/` are ordinary workspace files: commit them so collaborators get the skills
  without Spec Kit, or ignore them. `specify extension add` or `remove` run directly bypasses the
  copy step; run the bootstrap's `sync` afterwards.
- When several skills ship the same instruction file, the copy from the first skill by ID wins and a
  differing copy from another skill is reported.
- The SHA-256 record detects edits, not who made them; it is an audit aid, not tamper protection.
- Consumers of `skill` 1.0.0 keep the retired release-hosted catalog, which stops receiving new
  versions, until they reinstall the bootstrap with `--force`.

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
- [x] Limit each skill to one bump per branch and refuse bumps of unreleased skills; 50 Pester tests
      pass locally.
- [x] Document the design for consumers: README overview and FAQ, [architecture](architecture.md)
      with diagrams, [Spec Kit usage](spec-kit.md), the [skill catalogue](skills.md) and
      [end-to-end demos](demo.md).
- [x] Generate the catalog and an index page for GitHub Pages and add the deployment job; Pester
      covers the site output.
- [x] Add `upgrade-all` to the bootstrap (`skill` 1.1.0) with Pester coverage.
- [x] Track chosen versus required skills so `upgrade-all` offers newly related skills and `prune`
      removes skills no longer required (`skill` 1.2.0) with Pester coverage.
- [x] Enable Pages for this repository, merge, and confirm the deployed catalog and index resolve
      (PR #40, release `1.6.3`).
- [x] Record the Copilot discovery gap for extension-installed skills.
- [x] Copy installed guidance into `.github/` with SHA-256 audit records, add `remove` and `sync`,
      and keep modified copies on upgrade and removal (`skill` 1.3.0) with Pester coverage.
- [ ] Confirm in a fresh consumer that a copied skill is discovered in a new chat without `load`.
- [ ] Ship Bash and Python helper variants selected through the command's `scripts` map, with
      pytest and bats-core suites sharing the Pester scenarios and catalog fixtures (`skill` 1.4.0).
- [ ] Install from the published catalog with `specify init --script sh` and `--script py`
      consumers.
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
Later the same day, on `f2calv/2026-10-updates11`: the single-bump gate and unreleased-skill refusal
were added and 50 skill-library Pester tests passed; `dotnet-*` examples were aligned with the
strongly-typed configuration rule; the README was split into an overview with FAQ and diagrams plus
`docs/` pages for architecture, Spec Kit use, the catalogue, repository management and development.
The catalog then moved to GitHub Pages with a generated index page, the bootstrap gained
`upgrade-all`, and `docs/demo.md` scripted seven end-to-end demos; 54 skill-library tests passed.
[PR #40](https://github.com/f2calv/.github/pull/40) merged that branch (tag `1.6.3`): CI published
22 releases, including `skill/1.1.0` and `skill-library/1.0.2`, and deployed the catalog to
<https://f2calv.github.io/.github/>, where `catalog.json` lists 49 extensions.

**Windows host check (2026-10-31).** PowerShell 7.6, Git, GitHub CLI and `yq` v4 are present;
`uv` and the Specify CLI are not. Spec Kit's PowerShell is only the project scripts that
`specify init --script ps` copies into `.specify/scripts/powershell/`. The `specify` CLI itself,
which provides `init` and `extension add`, is Python only, and its releases include no
standalone executable. Where `uv` is unavailable, install it with pip into a virtual environment
using the host's configured package index: `python -m venv ~/.venvs/specify`, then
`~/.venvs/specify/Scripts/python -m pip install specify-cli==1.2.3` on Windows
(`bin/python` on Linux or macOS). The end-to-end consumer run on Windows has not started.

**State on 2026-11-02.** A Dev Container demo consumer installed `skill` 1.1.0, `docs-adr` and
`skill-library` from the Pages catalog; `load docs-adr` worked, but `.github/skills/` held only the
`speckit-*` commands, which exposed the [discovery gap](#discovery-gap). Decision 7 closes it on
`f2calv/2026-11-updates3`.

**Next session, part 0: demo the published catalog.** Run [demos 5 and 6](demo.md) against the
Pages catalog, then delete the stale `skills-catalog` release, which only the retired `skill` 1.0.0
bootstrap still reads.

**Next session, part 1: pin cascade (Dev Container).** `repository-privacy` is the only skill that
`docs-adr` requires; `terraform-infrastructure` lists it as related only.

1. Make a real change to `repository-privacy`, then run `git fetch --tags` and
   `./.github/skills/skill-library/scripts/Set-SkillVersion.ps1 -Id repository-privacy`.
2. Expect `repository-privacy` at `1.0.1`, and `docs-adr` patch-bumped past its latest tag with its
   required pin updated. `terraform-infrastructure` must not change. Run `Test-SkillLibrary.ps1`.
3. Merge, then confirm both new releases and their versions in the Pages catalog. Tick the
   pin-cascade box.

**Next session, part 2: Windows consumer.** Install PowerShell 7.4+, Git, GitHub CLI, `yq` v4
(`winget install MikeFarah.yq`) and the Specify CLI
(`uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v1.2.3`, or the pip
route above). Then:

1. Confirm the catalog resolves: `https://f2calv.github.io/.github/catalog.json`.
2. In a fresh demo repository, follow [Versioned Skills for Spec Kit](spec-kit.md).
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

**Unmerged branches.** `f2calv/2026-10-updates12` carries Agent Plugins packaging
(`skill-library/1.1.0`); its remaining work is tracked in
[ADR 0002](adr-0002-agent-plugins-packaging.md#handover).

## Open Questions

- Should the Pages index grow into a fuller skill browser, for example with facets and per-skill
  pages, or stay a single generated table?
- Should `upgrade-all` also refresh the `skill` bootstrap itself, or stay limited to skills?
