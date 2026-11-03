---
name: skill-library-vendoring
description: Adopt or upgrade the skill-library framework (tooling, Spec Kit bootstrap, tests and CI) in another repository that authors its own skills, syncing pinned framework files from a release tag. Use when bootstrapping a repository with the framework, upgrading it, bringing its existing skills up to the sidecar rules, or making a clean hard cut, with both repositories open.
---

# Skill Library Vendoring

Copy the [skill-library](../skill-library/SKILL.md) framework into a target repository and keep it
current from `skill-library/X.Y.Z` release tags. The target authors its own skills, publishes its own
catalog and never depends on this repository at run time.
[ADR 0004](https://github.com/f2calv/.github/blob/main/docs/adr-0004-skill-library-vendoring.md)
records the design.

## Boundaries

- **Never write target content to this repository.** With both repositories open, read the target
  only to adapt it. A generic fix found there is re-implemented here with synthetic examples,
  released, and then synced back. Names, paths, hosts and examples from the target stay there.
- **Never copy skills or instructions other than the framework.** The target's guidance replaces
  this repository's.
- **Change the target on a branch**, following its own commit and review rules.

## What the Framework Is

[framework.yaml](./framework.yaml) lists it, and the sync reads the copy at the chosen tag:

| Kind | Paths | Sync behaviour |
| --- | --- | --- |
| Managed | `.github/skills/skill-library/` except its sidecar, `src/skill-library-extension/` | Overwritten while the target's copy matches the lock; local edits are kept and reported |
| Seeded | `.github/skill-library.config.yaml`, the skill-library sidecar, `.github/workflows/skill-library.yml`, `docker-compose.yml`, `pyproject.toml`, `uv.lock` | Created once when missing, then owned by the target; an existing file is skipped |

The lock, `.github/skill-library.framework.lock.json`, records the source repository, tag, commit
and every file's SHA-256. Commit it with the synced files.

## Adopt

Needs PowerShell 7.4+, Git and Mike Farah `yq` v4.

1. In this repository, `git fetch --tags`. Preview, then sync into a clean branch of the target:

   ```powershell
   $Sync = './.github/skills/skill-library-vendoring/scripts/Sync-SkillLibraryFramework.ps1'
   & $Sync -Source . -Target <target> -WhatIf | Format-Table
   & $Sync -Source . -Target <target> | Format-Table
   ```

2. Fill in the seeded `.github/skill-library.config.yaml`: `catalogUrl` where the target publishes
   `catalog.json`, and a reverse-domain `pluginNamespace` the target's organisation owns. Set
   `catalogueDocument` only when the target keeps a skill catalogue page. The tooling rejects the
   template's `example.com` and `com.example` values.
3. Merge every `Skipped` file by hand: the target already had it, for example its own
   `docker-compose.yml` or `pyproject.toml`. Keep the `python-tests`, `bash-tests` and
   `pester-tests` services and the Python tool configuration that the framework tests need.
4. Bring the target's existing skills up to the rules, in the target:
   - `New-SkillMetadata.ps1` scaffolds a sidecar per skill. Review each: real `related` reasons,
     genuinely mandatory skills under `required`, and `externalFiles` for linked instructions.
   - `Test-SkillLibrary.ps1` reports the rest: `name` matching the folder, descriptions of at most
     1024 characters, links to undeclared skills or files, and catalogue rows.
   - `Measure-CustomizationContext.ps1 -Root ./.github` reports context-budget breaches; fix them
     with the [authoring reference](../skill-library/references/authoring-and-context-budget.md).
   - Skills keep their authored versions until their first release; nothing is tagged yet.
5. Adapt the seeded `.github/workflows/skill-library.yml` to the target's runners and host. On
   GitHub Enterprise Server, confirm that Pages is enabled and that `actions/deploy-pages` supports
   the server version, or host `catalog.json` elsewhere; set `GH_HOST` where `gh` needs the server's
   API host; and check that `specify extension add` can download private release assets with a token.
   Enable Pages once with `gh api -X POST repos/<owner>/<repo>/pages -f build_type=workflow`.
6. Run the framework tests in the target: the Pester suites under
   `.github/skills/skill-library/scripts/tests`, and `docker compose run --rm python-tests` and
   `bash-tests`.
7. Commit the sync on its own, naming the source tag, then the configuration and skill changes
   separately.

## Upgrade

1. `git fetch --tags` here, then run the sync with `-Ref skill-library/X.Y.Z -WhatIf` and without.
2. Resolve every `Kept` result. Either the change is generic, so re-implement it here and sync
   again, or it is deliberately local, so leave it; it stays `Kept` on every later sync.
3. Run `Set-SkillVersion.ps1 -Id skill-library` in the target, then `Test-SkillLibrary.ps1` and the
   tests. The target's skill-library version is its own, bumped once per sync.

## Results

| Action | Meaning |
| --- | --- |
| `Added` | New framework file written |
| `Updated` | Unedited copy replaced with the tag's version |
| `Unchanged` | Already identical |
| `Kept` | Locally edited, or present before the first sync; not touched |
| `Removed` | Retired from the framework and unedited, so deleted |
| `Seeded` | Created once from its template |
| `Skipped` | Seeded path already exists; merge by hand when needed |

## Hard Cut

Stop running the sync. The lock keeps recording the last tag taken, and every framework file is
then owned by the target. Nothing else needs removing.

## Maintaining This Skill

- Add every new framework file to [framework.yaml](./framework.yaml) in the same change; a managed
  file must not contain this repository's catalog host or plugin namespace, which
  `Framework.Tests.ps1` enforces.
- Keep the seeded CI template aligned with this repository's release jobs and action major versions.
- Recheck GitHub Enterprise Server support for Pages and `actions/deploy-pages` when either releases
  a new major version.
