---
name: skill-library
description: 'Version, package, release and install skills as Spec Kit extensions and Agent Plugins, and author or audit instructions and skills against a context budget: sidecars, version bumps with pin cascade, deterministic builds, portable frontmatter, the GitHub Pages catalog and token measurement. Use when changing a sidecar or skill version, fixing a failed version check, building or installing packages, or writing, splitting or auditing instructions and skills for token efficiency.'
---

# Skill Library

Each skill in `.github/skills/` is an independently versioned component, released as a Spec Kit
extension. The [ADR](https://github.com/f2calv/.github/blob/main/docs/adr-0001-skill-library-distribution.md)
records the design and delivery status.
Native consumption of the folders is unchanged. Tooling needs PowerShell 7.4+, Git and Mike Farah
`yq` v4 on Linux, macOS or Windows; install `yq` with `winget install MikeFarah.yq`, `brew install yq`
or your Linux package manager.

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

- `facets` are search tags: catalog `tags`, `/speckit-skill-library search` terms and plugin
  `keywords`. Reuse an existing facet before inventing one.
- `required` skills are always installed with this one, at the pinned version.
- `related` skills are offered with their `reason`; the user chooses whether to install them.
- `externalFiles` are repository-root-relative files under `.github/`, outside the folder, that the
  skill links to, typically instructions. Everything committed in the folder is packaged
  automatically; link other repository files by URL.
- Do not hand-edit `version` or required pins; use `Set-SkillVersion.ps1`.

The [sidecar reference](https://github.com/f2calv/.github/blob/main/docs/skill-metadata.md) explains
every field for human readers.

An optional `apm.yml` beside the sidecar makes a skill installable with APM (ADR 0003; `docs-adr` is
the pilot). `Test-SkillLibrary.ps1` requires its `name` and `version` to match the sidecar and its
`dependencies.apm` to list exactly `<owner>/<repo>/.github/skills/<id>#<id>/<version>` for each
required skill and `<owner>/<repo>/<file>#<this-id>/<this-version>` for each external file; edit it
after every bump. The Spec Kit and Agent Plugin packages leave it out.

## Author and Audit

Write, split and audit instructions and skills against the context budget in the
[authoring reference](references/authoring-and-context-budget.md): what every surface costs, what
belongs always-on, how to scope `applyTo`, description and front-matter style, and how to move
detail into references without losing rules. Measure before and after a change:

```powershell
./.github/skills/skill-library/scripts/Measure-CustomizationContext.ps1 -Root ./.github
```

It reports always-on and per-file instruction tokens, description tokens and the largest skills,
and warns on each budget breach; `-FailOnBudget` makes a breach fail.

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

Scaffolding, validation and packaging exclude Git-ignored local skill folders and the `speckit-*`
skills that `specify init` generates. If one appears in a
missing-sidecar error, repair ignore discovery rather than adding it to the public catalog.

`New-SkillMetadata.ps1` seeds `version: 1.0.0`, a facet from the folder prefix, related skills from
links to other skill folders and external files from links to other repository files. Review it:
replace generic `Linked from ...` reasons and move genuinely mandatory skills to `required`.

`Test-SkillLibrary.ps1` runs in CI. It fails when a skill has no sidecar, sidecars are invalid,
a document in a skill links to another skill not listed as required or related, or to a repository
file not listed in `externalFiles`, `docs/skills.md` does not list every skill once at its current
version,
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

### Agent Plugins

Every skill release also carries `<id>-<version>-plugin.zip`, an
[Agent Plugins](https://agent-plugins.org/specification) v1.0.0 package; add `-AgentPlugin` to a
local build to produce it. ADR 0002 under `docs/` records the design.

- `plugin.json` maps id, version, description and facets; `required` and `related` go under the
  `io.github.f2calv.skill-library` extension namespace because the format has no dependencies.
- The skill sits at `skills/<id>/`; external files drop their `.github/` prefix, so
  `../../instructions/<file>` links still resolve inside the plugin. `Test-SkillLibrary.ps1` rejects
  external files outside `.github/` before they can fail the build.
- `SKILL.md` frontmatter fields outside the [Agent Skills](https://agentskills.io/specification)
  set, such as `argument-hint` and `user-invocable`, move into `metadata` as strings in the package
  only. Sources keep them for VS Code.
- `Test-SkillLibrary.ps1` checks the normalised frontmatter: `name` matches the folder, a
  1-1024 character `description`, `compatibility` up to 500 characters and string `metadata`.
- Instructions in a plugin are linked reference files; clients do not apply them by `applyTo`.
- Releases published before this packaging have no plugin asset; a skill gains one on its next bump.

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

`--script sh` and `--script py` select the Bash and Python variants of the helper instead; the
command's `scripts` map names all three, and their behaviour is identical.

Then use `/speckit-skill-library search architecture`, `/speckit-skill-library install docs-adr` and
`/speckit-skill-library load docs-adr`. The command plans the install, asks which related skills to
add and runs `specify extension add` for each skill in dependency order. Spec Kit verifies each
archive's SHA-256 from the catalog and unpacks skills under `.specify/extensions/<id>/`, which
Copilot never scans, because Spec Kit 1.2.3 has no skill package type. The helper therefore copies
each enabled skill's `resources/.github/` into the workspace `.github/` after every install,
upgrade, `remove`, `prune` and `sync`, recording each copy's SHA-256, skill, version and date. It
replaces or deletes a copy only while its bytes match that record and reports modified or unmanaged
files as `Kept`.
`/speckit-skill-library upgrade-all` moves every installed skill to its latest catalog version with
`specify extension add --force`, required skills first, and installs skills an upgraded version
newly requires. It offers related skills that an upgraded version newly lists and reports skills no
chosen skill requires any more; `/speckit-skill-library prune` removes those with
`specify extension remove --force`, and `remove <id>` removes one chosen skill nothing else requires.
The helper records whether each skill was chosen or only
required, with its version and enabled flag, in `.specify/extensions/.skill-library.json`, because
Spec Kit's registry stores only versions; skills installed before that file existed count as chosen
and are never pruned. Spec Kit has no install or uninstall hooks and cannot protect an extension, so
every command except `help` warns about skills removed, installed, upgraded, enabled or disabled with
`specify extension` directly, and each skill's generated `extension.yml` description says it is
managed by the skill library.
`upgrade-all` does not upgrade the `skill` bootstrap, which `specify extension add skill --force`
replaces.

Every script in `scripts/` has a matching `tests/<Name>.Tests.ps1`; the consumer helper's tests live
there too so they are not packaged into the bootstrap. A repository test enforces the pairing.

## Maintaining This Skill

- Context budgets and the cost model whenever a client changes how it loads instructions, skill
  descriptions or skill resources; lessons from each library audit go in the authoring reference.
- Spec Kit releases: recheck `extension.yml` fields, `provides.templates`, the catalog `releases`
  format, `SPECKIT_CATALOG_URL` precedence and the catalog cache file naming used by the helper.
  Watch for extension install or remove lifecycle hooks or a protected/managed-by field, which
  would let the helper's drift warnings become a prompt at removal time.
- `yq` major versions: recheck `-i` comment preservation and YAML/JSON conversion.
- Git ignore discovery on Windows and paths requiring Git quoting: verify ignored skills with and
  without sidecars remain excluded, and Git failures are reported rather than treated as unignored.
- GitHub release asset URLs for tags containing `/`, and the Pages URL for a dot-named repository.
- `actions/upload-pages-artifact` and `actions/deploy-pages` major versions and permissions.
- `specify extension add --force` semantics, which `upgrade-all` relies on.
- Agent Plugins and Agent Skills specification versions: the `$schema` URL, the closed manifest
  fields, the portable frontmatter field list and name, description and compatibility limits.
