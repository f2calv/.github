# Skill Metadata Sidecar

Every skill folder carries a `skill.metadata.yaml` file next to its `SKILL.md`. `SKILL.md` tells an
agent what the skill does and when to use it; the sidecar tells the release tooling how the skill is
versioned, what it depends on and how it is found in the catalog. Copilot never reads the sidecar,
so it costs no context.

The component ID is the folder name, so the sidecar does not repeat it. The
[JSON schema](../.github/skills/skill-library/skill-metadata.schema.json) is the formal definition;
editors that understand the `yaml-language-server` comment validate the file as you type.

## Example

```yaml
# yaml-language-server: $schema=../skill-library/skill-metadata.schema.json
version: 1.0.2
facets: [documentation, architecture]
required:
  - id: repository-privacy
    version: 1.1.0
related:
  - id: github-issues-and-pull-requests
    reason: Publish or track an ADR as a GitHub issue.
externalFiles:
  - .github/instructions/markdown.instructions.md
```

Only `version` is mandatory. The smallest valid sidecar is:

```yaml
# yaml-language-server: $schema=../skill-library/skill-metadata.schema.json
version: 1.0.0
facets: [tooling]
```

## Fields

| Field | Required | Shape | Meaning |
| --- | --- | --- | --- |
| `version` | Yes | `X.Y.Z` | The skill's own semantic version, released as the Git tag `<id>/X.Y.Z` |
| `facets` | No | List of lowercase slugs | Search tags for finding the skill in the catalog |
| `required` | No | List of `id` and `version` | Skills always installed with this one, each pinned to an exact version |
| `related` | No | List of `id` and `reason` | Skills offered alongside this one; the user chooses whether to install each |
| `externalFiles` | No | List of repository-relative paths under `.github/` | Files outside the skill folder that the skill links to and that must be packaged with it |

### `version`

Each skill is versioned independently: `major` for breaking guidance changes, `minor` for new
capability and `patch` for fixes. Never edit it by hand; `Set-SkillVersion.ps1` bumps it, at most
once per branch, and updates every pin and the [skill catalogue](skills.md) row with it. A skill
that has never been released keeps its authored version until its first release.

### `facets`

Facets are free-form tags that classify a skill by area or topic. They have no effect on how Copilot
loads or runs the skill. After a release they appear as:

- `tags` in the published `catalog.json` and on the GitHub Pages index;
- the terms `/speckit-skill-library search` matches, alongside the skill ID and description;
- `keywords` in the skill's Agent Plugin `plugin.json`.

`New-SkillMetadata.ps1` seeds one facet from the folder prefix, such as `dotnet` for
`dotnet-redis`. Keep one area facet that several skills share, add a topic facet only when it helps
someone searching (`scheduling`, `identity`), and reuse an existing facet before inventing a new
one. To list the facets in use:

```powershell
Get-ChildItem .github/skills/*/skill.metadata.yaml | Select-String '^facets:' |
  ForEach-Object { ($_.Line -replace '^facets:\s*\[|\]', '') -split ',\s*' } | Group-Object | Sort-Object Count -Descending
```

### `required` and `related`

A **required** skill is one this skill cannot work without: it is installed first, at exactly the
pinned version, and a pin that cannot be met stops the install. A **related** skill is a useful
companion: the installer shows its `reason` and installs it only when the user accepts.

| | `required` | `related` |
| --- | --- | --- |
| Installed | Always, before this skill | Only when the user chooses it |
| Version | Exactly the pinned `version` | The current catalog version |
| Upgrades | Installed automatically when a new version adds it | Offered when a new version adds it |
| Removal | `prune` removes it once no chosen skill requires it | Kept until `remove`, because the user chose it |
| When to use | The skill's workflow depends on the other skill | The other skill is a natural next step |

Pins are maintained by `Set-SkillVersion.ps1`: bumping a required skill updates every pin to it and
gives each released dependant a patch bump. Required skills must not form a cycle.

`New-SkillMetadata.ps1` adds every skill linked from the skill's Markdown as related with a generic
`Linked from ...` reason. Replace that with a reason a user can act on, and move genuinely mandatory
skills to `required`.

### `externalFiles`

A release packages every committed file in the skill folder automatically. List here only files
outside it that the skill links to, typically shared instructions. Each path is relative to the
repository root and must sit under `.github/`, so that links still resolve inside the Spec Kit
extension and the Agent Plugin. Link anything else, such as a repository-root configuration file, by
its GitHub URL instead.

## Validation

`Test-SkillLibrary.ps1` runs in CI and fails when:

- a skill folder has no sidecar, or a sidecar breaks the schema;
- a Markdown file in the skill links to another skill not listed in `required` or `related`, or to a
  repository file not listed in `externalFiles`;
- an external file is missing, already inside the skill folder or outside `.github/`;
- required skills form a cycle, or a pin differs from the required skill's version;
- a changed skill was not bumped, or was bumped more than one step past its last release;
- the [skill catalogue](skills.md) does not list the skill once at its current version.

Each error names the script that fixes it. The
[skill library workflow](../.github/skills/skill-library/SKILL.md#validate-and-bump) gives the
commands to run before committing.

## Where the Values Go

| Sidecar field | Spec Kit extension and catalog | Agent Plugin `plugin.json` |
| --- | --- | --- |
| `version` | `extension.version` and the catalog entry's `version` | `version` |
| `facets` | Catalog `tags` | `keywords` |
| `required` | Catalog `skill_library.required` | The `io.github.f2calv.skill-library` extension namespace |
| `related` | Catalog `skill_library.related` | The `io.github.f2calv.skill-library` extension namespace |
| `externalFiles` | Packaged under `resources/` at their repository paths | Packaged with the `.github/` prefix removed |

The skill's `SKILL.md` front matter supplies the description everywhere.

## Not to Be Confused With

A Spec Kit repository that installs skills through `/speckit-skill-library` gets a different file,
`.specify/extensions/.skill-library.json`. It records whether the user chose each installed skill or
it was installed only as a requirement, so that `upgrade-all` and `prune` can tell them apart, and
the SHA-256 of every file copied into `.github/`, so that local edits survive upgrades and removals.
Sidecars describe published skills; that file describes one consumer's installation.
