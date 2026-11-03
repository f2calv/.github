# Versioned Skills for Spec Kit

Spec Kit users can install selected skills at exact versions instead of consuming the whole
repository. Each skill is published as a Spec Kit extension in a GitHub Release named
`<skill>/X.Y.Z`, and one catalog on [GitHub Pages](https://f2calv.github.io/.github/) lists every
published version. Native Copilot consumption, described in the [README](../README.md), remains the
default and needs none of this.

## Prerequisites

- The [Specify CLI](https://github.com/github/spec-kit), initialized in the consuming repository.
- Network access to GitHub Pages and this repository's GitHub Releases.
- The runtime of the helper variant Spec Kit selects from `specify init --script`:

  | `--script` | Helper | Needs |
  | --- | --- | --- |
  | `ps` | `Invoke-SkillLibrary.ps1` | PowerShell 7.4 or later |
  | `sh` | `bash/skill-library.sh` | Bash 4 or later, `jq`, `sha256sum` or `shasum`, and `curl` |
  | `py` | `python/skill_library.py` | The Python that runs the Specify CLI; no packages |

  All three accept the same commands and arguments, print the same output and share one state file,
  so changing `--script` later keeps installed skills. macOS ships Bash 3.2: choose `ps` or `py` there,
  or install a newer Bash.

## Install the Bootstrap Command

Add the `skill` extension once per consuming repository. It provides the `/speckit-skill-library`
command.

```powershell
specify init --here --integration copilot --script ps
$env:SPECKIT_CATALOG_URL = 'https://f2calv.github.io/.github/catalog.json'
specify extension add skill
Remove-Item Env:SPECKIT_CATALOG_URL
```

With Bash, choose `--script sh` or `--script py`:

```bash
specify init --here --integration copilot --script sh
SPECKIT_CATALOG_URL=https://f2calv.github.io/.github/catalog.json specify extension add skill
```

Repositories that installed `skill` 1.0.0 use the retired release-hosted catalog, which no longer
receives new versions. Rerun the commands above with `specify extension add skill --force` to switch.

## Install and Load Skills

In Copilot Chat in the consuming repository:

```text
/speckit-skill-library search architecture
/speckit-skill-library install docs-adr
/speckit-skill-library load docs-adr
```

`search` matches skill IDs, descriptions and each skill's
[facets](skill-metadata.md#facets), such as `architecture` or `dotnet`.

`install` resolves the skills the selected skill requires, at their pinned versions, and offers its
related skills for explicit selection. It then installs each through `specify extension add`, which
verifies every archive's SHA-256 digest from the catalog. Spec Kit unpacks each skill under
`.specify/extensions/<skill>/`.

## Copilot Discovery

Spec Kit has no skill package type, and Copilot never scans `.specify/extensions/`. After every
`install`, `upgrade-all`, `remove` and `prune`, the helper therefore copies each installed skill's
folder into `.github/skills/<skill>/` and its instructions into `.github/instructions/`, where
Copilot discovers the skill in every new chat and applies the instructions by `applyTo`. `load`
brings a skill into the current chat without starting a new one.

Each copy's SHA-256, source skill, version and copy date are recorded in
`.specify/extensions/.skill-library.json`. A copy is replaced or deleted only while its bytes still
match that record. A locally modified copy, or a file the helper did not write, is kept and
reported with a `Kept` line, so upgrading or removing a skill never silently discards local edits.
Commit the copies so collaborators get the skills without Spec Kit, or ignore them; either works.

## Direct Spec Kit Commands

Spec Kit has no install or uninstall hooks and no way to protect an extension, so nothing stops
`specify extension add`, `remove`, `enable` or `disable` being run against a skill directly. The
helper detects that instead: the state file records every installed skill's version and enabled
flag, and every command except `help` first prints a `Warning:` line for each skill removed,
installed, upgraded, enabled or disabled outside the skill library, followed by a reminder to use
`/speckit-skill-library`. Run `/speckit-skill-library sync` to bring `.github/` back in line, or
`install <skill>` to restore a removed skill another skill requires. Each skill extension's
description, shown by `specify extension list` and `info`, also says it is managed by the skill
library.

## Upgrade Installed Skills

```text
/speckit-skill-library upgrade-all
```

`upgrade-all` compares every installed skill with the catalog, prints each one as `current` or
`upgrade from X`, and replaces outdated skills through `specify extension add --force`, required
skills first. It also installs any skill newly required by an upgraded version. If a required pin
cannot be met it stops before changing anything. It does not upgrade the `skill` bootstrap itself.

After upgrading it lists related skills that an upgraded version newly offers, for you to install by
choice, and names skills that no chosen skill requires any more, for example after an upgraded skill
dropped a dependency. Remove those with:

```text
/speckit-skill-library prune
```

The helper records in `.specify/extensions/.skill-library.json` whether you chose each skill or it
was installed only as a requirement; `list` shows that as `chosen` or `required`. Skills you
requested or selected are never pruned, and skills installed before the file existed count as
chosen.

## Versions

Each skill follows semantic versioning independently: `major` for breaking guidance changes, `minor`
for new capability and `patch` for fixes. A skill's required skills are pinned to exact versions;
related skills install at their current catalog version. Published releases never change.

Installing a skill directly with `specify extension add <skill>` skips its required skills and the
copy into `.github/`; use the bootstrap command instead. To remove a skill you chose, use
`/speckit-skill-library remove <skill>`, which refuses while another installed skill requires it;
`prune` removes only skills no chosen skill requires.

## Further Reading

- [Skill catalogue](skills.md): what each skill is for.
- [Skill metadata sidecar](skill-metadata.md): what each field of `skill.metadata.yaml` means.
- [End-to-end demos](demo.md): install, load and upgrade walkthroughs.
- [Skill library workflow](../.github/skills/skill-library/SKILL.md): sidecars, version bumps and
  releases, for maintainers.
- [ADR 0001](adr-0001-skill-library-distribution.md): the distribution design and its status.
