---
name: skill-library
description: 'Version, package, release and install skills as Spec Kit extensions: skill.metadata.yaml sidecars, required and related skills, version bumps with pin cascade, deterministic ZIP builds, GitHub Releases with a rolling catalog, and the /speckit-skill-library bootstrap command. Use when adding or changing a sidecar, bumping a skill version, fixing a failed skill version check, or installing skills into a Spec Kit repository.'
---

# Skill Library

Each skill in `.github/skills/` is an independently versioned component, released as a Spec Kit
extension. The [ADR](../../../docs/adr-0001-skill-library-distribution.md) records the design.
Native consumption of the folders is unchanged. Tooling needs PowerShell 7.4+, Git and `yq` v4.

## Sidecar

Every skill folder has `skill.metadata.yaml`, validated by the
[schema](./skill-metadata.schema.json). The component ID is the folder name.

```yaml
# yaml-language-server: $schema=../skill-library/skill-metadata.schema.json
version: 1.0.0
facets: [documentation, architecture]
required:
  - id: repository-privacy
    version: 1.0.0
related:
  - id: github-issues-and-pull-requests
    reason: Publish or track an ADR as a GitHub issue.
externalFiles:
  - .github/instructions/markdown.instructions.md
```

- `required` skills are always installed with this one, at the pinned version.
- `related` skills are offered with their `reason`; the user chooses whether to install them.
- `externalFiles` are repository-root-relative files outside the folder the skill depends on,
  typically instructions it links to. Everything committed in the folder is packaged automatically.
- Do not hand-edit `version` or required pins; use `Set-SkillVersion.ps1`.

## Validate and Bump

```powershell
./.github/skills/skill-library/scripts/Test-SkillLibrary.ps1
./.github/skills/skill-library/scripts/Set-SkillVersion.ps1                     # patch every changed released skill
./.github/skills/skill-library/scripts/Set-SkillVersion.ps1 -Id dotnet-redis -Bump minor
```

`Test-SkillLibrary.ps1` runs in CI. It fails when sidecars are invalid, required skills form a cycle,
a skill or its external files changed since its last `<id>/X.Y.Z` tag without a version bump, or a
required pin differs from the required skill's version.

`Set-SkillVersion.ps1` bumps from the last released tag, so rerunning it is safe. It updates the pins
in skills that require the bumped skill and gives released dependents a patch bump, recursively.
Unreleased skills keep their authored version unless named. Use `major` for breaking guidance
changes, `minor` for new capability and `patch` for fixes.

## Build and Release

```powershell
./.github/skills/skill-library/scripts/Build-SkillExtension.ps1 -Id docs-adr -OutputDirectory ./artifacts
./.github/skills/skill-library/scripts/Publish-SkillRelease.ps1 -DryRun
```

A build packages committed files only and refuses uncommitted changes. The ZIP contains
`extension.yml` and the files under `resources/<repository path>`, so relative links between the
skill and its external files still resolve. Rebuilds are byte-identical.

On `main`, CI runs `Publish-SkillRelease.ps1`. Every component whose version has no tag is published
as GitHub Release `<id>/X.Y.Z`, then `catalog.json` on the rolling `skills-catalog` release is
regenerated from all releases. Published releases are never changed.

The `skill` bootstrap extension lives in [src/skill-library-extension](../../../src/skill-library-extension/).
It is versioned in its `extension.yml` and released as `skill/X.Y.Z` the same way.

For a local end-to-end test, add `-CatalogBaseUrl http://localhost:8765/` to a build, serve the output
directory on that port, and set `SPECKIT_CATALOG_URL` and `SKILL_LIBRARY_CATALOG_URL` to its
`catalog.json` in the consumer.

## Install in a Consumer

```powershell
specify init --here --integration copilot --script ps
$env:SPECKIT_CATALOG_URL = 'https://github.com/f2calv/.github/releases/download/skills-catalog/catalog.json'
specify extension add skill
Remove-Item Env:SPECKIT_CATALOG_URL
```

Then use `/speckit-skill-library search architecture`, `/speckit-skill-library install docs-adr` and
`/speckit-skill-library load docs-adr`. The command plans the install, asks which related skills to
add and runs `specify extension add` for each skill in dependency order. Spec Kit verifies each
archive's SHA-256 from the catalog. Installed skills are read from `.specify/extensions/<id>/`.

## Maintaining This Skill

- Spec Kit releases: recheck `extension.yml` fields, `provides.templates`, the catalog `releases`
  format, `SPECKIT_CATALOG_URL` precedence and the catalog cache file naming used by the helper.
- `yq` major versions: recheck `-i` comment preservation and YAML/JSON conversion.
- GitHub release asset URLs for tags containing `/`.
- Move the catalog to GitHub Pages if the rolling release becomes awkward.
