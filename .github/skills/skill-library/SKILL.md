---
name: skill-library
description: 'Version, package, release and install skills as Spec Kit extensions: skill.metadata.yaml sidecars, required and related skills, version bumps with pin cascade, deterministic ZIP builds, GitHub Releases with a GitHub Pages catalog, and the /speckit-skill-library bootstrap command. Use when adding or changing a sidecar, bumping a skill version, fixing a failed skill version check, or installing skills into a Spec Kit repository.'
---

# Skill Library

Each skill in `.github/skills/` is an independently versioned component, released as a Spec Kit
extension. The [ADR](https://github.com/f2calv/.github/blob/main/docs/adr-0001-skill-library-distribution.md)
records the design and delivery status.
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

After adding or changing any skill, before committing:

```powershell
git fetch --tags
./.github/skills/skill-library/scripts/New-SkillMetadata.ps1                    # scaffold sidecars for new skills
./.github/skills/skill-library/scripts/Set-SkillVersion.ps1                     # patch every changed released skill
./.github/skills/skill-library/scripts/Set-SkillVersion.ps1 -Id dotnet-redis -Bump minor
./.github/skills/skill-library/scripts/Test-SkillLibrary.ps1
```

Fetch tags first: the checks compare against `<id>/X.Y.Z` tags that CI creates on GitHub. Without
them every skill looks unreleased and the local check passes while CI fails.

`New-SkillMetadata.ps1` seeds `version: 1.0.0`, a facet from the folder prefix, related skills from
links to other skill folders and external files from links to other repository files. Review it:
replace generic `Linked from ...` reasons and move genuinely mandatory skills to `required`.

`Test-SkillLibrary.ps1` runs in CI. It fails when a skill has no sidecar, sidecars are invalid,
required skills form a cycle, a skill or its external files changed since its last `<id>/X.Y.Z` tag
without a version bump, a version is more than one patch, minor or major step past its last tag,
or a required pin differs from the required skill's version. Each error names the script that fixes it.

A skill gets at most one bump per branch, however many times it changes before the pull request
merges: `1.0.0` becomes `1.0.1`, not `1.0.3`. `Set-SkillVersion.ps1` bumps from the last released
tag, so rerunning it during a long session is safe and never stacks bumps. It updates the pins
in skills that require the bumped skill and gives released dependents a patch bump, recursively.
Unreleased skills are never bumped: their first release uses the authored version. Use `major` for
breaking guidance changes, `minor` for new capability and `patch` for fixes.

## Build and Release

```powershell
./.github/skills/skill-library/scripts/Build-SkillExtension.ps1 -Id docs-adr -OutputDirectory ./artifacts
./.github/skills/skill-library/scripts/Publish-SkillRelease.ps1 -DryRun
```

A build packages committed files only and refuses uncommitted changes. The ZIP contains
`extension.yml` and the files under `resources/<repository path>`, so relative links between the
skill and its external files still resolve. Rebuilds are byte-identical.

On `main`, CI runs `Publish-SkillRelease.ps1`. Every component whose version has no tag is published
as GitHub Release `<id>/X.Y.Z`, which also creates that tag on the merge commit. Then `catalog.json`
and an `index.html` listing every skill are regenerated from all releases and deployed to GitHub
Pages at <https://f2calv.github.io/.github/>. The ZIPs stay on the releases. Published releases are
never changed. Versions live only in sidecars and tags; `package.json` holds test scripts.

Pages needs a one-time repository setting with the GitHub Actions source; the repository baseline
does not manage it because only this repository publishes a site:

```powershell
gh api -X POST repos/f2calv/.github/pages -f build_type=workflow
```

The `skill` bootstrap extension lives in [src/skill-library-extension](../../../src/skill-library-extension/).
It is versioned in its `extension.yml` and released as `skill/X.Y.Z` the same way.

For a local end-to-end test, add `-CatalogBaseUrl http://localhost:8765/` to a build, serve the output
directory on that port, and set `SPECKIT_CATALOG_URL` and `SKILL_LIBRARY_CATALOG_URL` to its
`catalog.json` in the consumer.

## Install in a Consumer

```powershell
specify init --here --integration copilot --script ps
$env:SPECKIT_CATALOG_URL = 'https://f2calv.github.io/.github/catalog.json'
specify extension add skill
Remove-Item Env:SPECKIT_CATALOG_URL
```

Then use `/speckit-skill-library search architecture`, `/speckit-skill-library install docs-adr` and
`/speckit-skill-library load docs-adr`. The command plans the install, asks which related skills to
add and runs `specify extension add` for each skill in dependency order. Spec Kit verifies each
archive's SHA-256 from the catalog. Installed skills are read from `.specify/extensions/<id>/`.
`/speckit-skill-library upgrade-all` moves every installed skill to its latest catalog version with
`specify extension add --force`, required skills first; it does not upgrade the `skill` bootstrap,
which `specify extension add skill --force` replaces.

Every script in `scripts/` has a matching `tests/<Name>.Tests.ps1`; the consumer helper's tests live
there too so they are not packaged into the bootstrap. A repository test enforces the pairing.

## Maintaining This Skill

- Spec Kit releases: recheck `extension.yml` fields, `provides.templates`, the catalog `releases`
  format, `SPECKIT_CATALOG_URL` precedence and the catalog cache file naming used by the helper.
- `yq` major versions: recheck `-i` comment preservation and YAML/JSON conversion.
- GitHub release asset URLs for tags containing `/`, and the Pages URL for a dot-named repository.
- `actions/upload-pages-artifact` and `actions/deploy-pages` major versions and permissions.
- `specify extension add --force` semantics, which `upgrade-all` relies on.
