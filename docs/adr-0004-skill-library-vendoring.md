# ADR 0004: Skill Library Framework Vendoring

**Status:** Proposed.
**Date:** 2026-11-03.
**Scope:** How another repository adopts and later upgrades the skill-library framework (the
maintainer tooling, the `skill` bootstrap extension and their tests) while authoring only its own
skills. Consuming this repository's skills is covered by
[ADR 0001](adr-0001-skill-library-distribution.md) and is out of scope.

## Context and Problem

ADR 0001 built the framework in this repository and proved it on the repository's own skills: a
sidecar per skill, per-skill `<id>/X.Y.Z` releases, a Spec Kit extension and Agent Plugin per release,
a Pages catalog and the `skill` bootstrap that installs skills into `.github/`. An organisation with
its own skills can use the same framework for them. Typical constraints:

- The adopting repository is private, often on GitHub Enterprise Server, and must not depend at run
  time on extensions or catalogs served from this public repository.
- It authors its own skills and instructions and takes none of this repository's content.
- It wants this repository's framework fixes for a while, and may stop taking them at any point.
- Nothing about the adopting organisation may flow back into this public repository.

Source-confirmed obstacles to copying the framework as it stands:

| Coupling | Where |
| --- | --- |
| Default catalog URL `https://f2calv.github.io/.github/catalog.json` | [Invoke-SkillLibrary.ps1](../src/skill-library-extension/scripts/Invoke-SkillLibrary.ps1), [skill_library.py](../src/skill-library-extension/scripts/python/skill_library.py), [skill-library.sh](../src/skill-library-extension/scripts/bash/skill-library.sh) |
| Agent Plugin namespace `io.github.f2calv.skill-library`, bootstrap ID and path | [SkillLibrary.psm1](../.github/skills/skill-library/scripts/SkillLibrary.psm1) |
| A mandatory `docs/skills.md` listing every skill | `Test-SkillCatalogue` in [SkillLibrary.psm1](../.github/skills/skill-library/scripts/SkillLibrary.psm1) |
| Release, catalog and Pages jobs inline in this repository's CI | [ci.yml](../.github/workflows/ci.yml) `skill-releases` |
| Maintainer tooling shipped only inside the `skill-library` skill's `scripts/` folder | [skill-library SKILL.md](../.github/skills/skill-library/SKILL.md) |

Each hardcoded value forces a text substitution when the file is copied, so the copy differs from
upstream and every later upgrade becomes a manual merge.

Unknown for a private GitHub Enterprise Server: whether Pages is available, whether the GitHub-hosted
actions the release job uses are reachable, whether `specify extension add` downloads private release
assets with a token, and whether the publishing script works against the server API host (`GH_HOST`).

## Goals and Constraints

- **V1** Framework files copy byte for byte; every repository-specific value lives in one
  configuration file owned by the adopting repository. This repository uses the same file.
- **V2** A sync copies from an immutable release tag, never from a working tree, and records the
  source tag and each file's SHA-256 in the target.
- **V3** A sync overwrites a framework file only while it matches its record and reports local
  edits, mirroring the bootstrap helper's `Kept` rule.
- **V4** Stopping syncs needs no clean-up; the record shows the last tag taken.
- **V5** Nothing from the target repository is written to this repository; generic fixes are
  re-implemented here with synthetic examples.
- Non-goals: distributing this repository's skills to the adopter, serving a shared catalog, and
  merging the adopter's changes back automatically.

## Options Considered

| Option | Benefits | Costs and risks | Assessment |
| --- | --- | --- | --- |
| Copy files by hand and edit them | Nothing to build | Untraceable divergence; every upgrade is a manual merge; easy to leak values either way | Rejected |
| Install the `skill-library` skill and bootstrap from this repository's catalog | Upgrades through existing commands | Run-time dependency on a public personal repository; tooling version tied to skill content; a private server may not reach it | Rejected |
| Fork, or a Git submodule or subtree of this repository | Git-native history | Carries every skill and instruction; submodules need access to the public host at clone time | Rejected |
| Publish the tooling as a PowerShell module and a reusable workflow | Versioned dependency | Still a run-time dependency on public hosting; leaves the Bash and Python helpers and tests behind | Deferred; reconsider if several adopters want live updates |
| Externalise configuration, list the framework files, and sync them from a tag with a recorded lock, driven by a skill | Byte-identical copies, traceable upgrades, clean hard cut, offline target | A list of files and a sync script to maintain | **Proposed** |

## Proposed Decision

1. **Configuration.** Move the catalog URL, plugin namespace and the optional catalogue document path
   into [`.github/skill-library.config.yaml`](../.github/skill-library.config.yaml), validated by a
   [schema](../.github/skills/skill-library/skill-library-config.schema.json). The tooling reads it and
   fails without it or with template example values; the bootstrap build writes the catalog URL into
   the packaged extension as `skill-library.json`, which the helpers read after `-CatalogUrl` and
   `SKILL_LIBRARY_CATALOG_URL`. The bootstrap ID and path stay fixed because the bootstrap is itself
   a managed framework file.
2. **Framework manifest.** One committed file lists framework paths in two groups: *managed*, which a
   sync overwrites (tooling scripts and tests, the bootstrap extension, the sidecar schema, the
   reusable test workflow, the Python and Bash test setup), and *seeded*, which a sync creates once
   and the target then owns (configuration, a CI release-job template, test service definitions,
   `package.json`). Skills other than `skill-library` are never framework.
3. **Sync script.** A script, illustratively
   `Sync-SkillLibraryFramework.ps1 -Source <clone> -Ref skill-library/X.Y.Z -Target <repo> [-WhatIf]`,
   reads the manifest at the tag, copies managed files under V2 and V3, creates missing seeded files,
   and writes a lock file (illustratively `.github/skill-library.framework.lock.json`).
4. **Skill.** A new skill drives adoption and upgrades with both repositories open: run the sync with
   `-WhatIf`, then for real; fill in configuration for the target host; bring the target's existing
   skills up to the sidecar and Agent Skills rules with `New-SkillMetadata.ps1`,
   `Test-SkillLibrary.ps1` and `Measure-CustomizationContext.ps1`; set up CI from the template; and
   run the tests. It states V5 explicitly.

## Consequences

- Adoption becomes a repeatable, reviewable change in the target repository, and upgrades are a
  tag bump. A hard cut is simply not running the sync again.
- This repository gains a configuration layer, a manifest that must list every new framework file,
  and a sync script with its own tests. A framework file missing from the manifest silently stays
  stale in adopters, so the manifest needs a completeness check.
- Local edits in an adopter are visible on every sync instead of being overwritten or lost.
- The adopter still owns hosting decisions: catalog location, Pages or release assets, and access
  tokens for private release downloads.

## Validation and Delivery

- [x] Configuration externalised: the config file and schema, the three helpers reading the packaged
  catalog URL, and the plugin namespace and catalogue page taken from configuration. Pester 135/135,
  pytest 27/27 and bats 27/27 with shellcheck pass, and this repository's packages are unchanged apart
  from the bootstrap's new `skill-library.json`.
- [ ] Framework manifest with a completeness check in `Test-SkillLibrary.ps1`.
- [ ] Sync script with Pester coverage: managed overwrite, locally edited file kept, seeded file
  created once, lock contents, `-WhatIf`.
- [ ] The adoption skill, released through the normal skill pipeline.
- [ ] Spike on a private GitHub Enterprise Server: catalog hosting, release-job actions, private asset
  download through `specify extension add`, and `GH_HOST` publishing.
- [ ] One adopting repository synced and its CI green, recorded here without identifying it.

## Open Questions and Reconsideration

- Should the reusable CI workflow be referenced across hosts, or always seeded as a template? A
  private server cannot call a workflow on github.com without GitHub Connect.
- Should the `skill-library` skill itself be a managed framework file in adopters, or replaced by
  the adoption skill's guidance?
- If several adopters want continuous updates, revisit the published-module option.

## Evidence and Related Decisions

| Evidence | Relevance |
| --- | --- |
| [ADR 0001](adr-0001-skill-library-distribution.md) | Framework, versioning and catalog being vendored |
| [ADR 0002](adr-0002-agent-plugins-packaging.md) | Agent Plugin namespace that becomes configuration |
| [ADR 0003](adr-0003-apm-distribution.md) | APM route an adopter can also enable for its own skills |
| [Invoke-SkillLibrary.ps1](../src/skill-library-extension/scripts/Invoke-SkillLibrary.ps1) | Bootstrap helper `Kept` rule that the sync mirrors |
| [SkillLibrary.psm1](../.github/skills/skill-library/scripts/SkillLibrary.psm1) | Hardcoded values and validation to externalise |
| [ci.yml](../.github/workflows/ci.yml) | Release and Pages jobs to template |
