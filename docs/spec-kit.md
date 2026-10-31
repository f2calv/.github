# Versioned Skills for Spec Kit

Spec Kit users can install selected skills at exact versions instead of consuming the whole
repository. Each skill is published as a Spec Kit extension in a GitHub Release named
`<skill>/X.Y.Z`, and one catalog lists every published version. Native Copilot consumption, described
in the [README](../README.md), remains the default and needs none of this.

## Prerequisites

- The [Specify CLI](https://github.com/github/spec-kit), initialized in the consuming repository.
- PowerShell 7.4 or later, used by the bootstrap command.
- Network access to this repository's GitHub Releases.

## Install the Bootstrap Command

Add the `skill` extension once per consuming repository. It provides the `/speckit-skill-library`
command.

```powershell
specify init --here --integration copilot --script ps
$env:SPECKIT_CATALOG_URL = 'https://github.com/f2calv/.github/releases/download/skills-catalog/catalog.json'
specify extension add skill
Remove-Item Env:SPECKIT_CATALOG_URL
```

## Install and Load Skills

In Copilot Chat in the consuming repository:

```text
/speckit-skill-library search architecture
/speckit-skill-library install docs-adr
/speckit-skill-library load docs-adr
```

`install` resolves the skills the selected skill requires, at their pinned versions, and offers its
related skills for explicit selection. It then installs each through `specify extension add`, which
verifies every archive's SHA-256 digest from the catalog. Installed skills live under
`.specify/extensions/<skill>/`.

## Versions

Each skill follows semantic versioning independently: `major` for breaking guidance changes, `minor`
for new capability and `patch` for fixes. A skill's required skills are pinned to exact versions;
related skills install at their current catalog version. Published releases never change.

Installing a skill directly with `specify extension add <skill>` skips its required skills; use the
bootstrap command instead. The bootstrap command does not upgrade or remove installed skills.

## Further Reading

- [Skill catalogue](skills.md): what each skill is for.
- [Skill library workflow](../.github/skills/skill-library/SKILL.md): sidecars, version bumps and
  releases, for maintainers.
- [ADR 0001](adr-0001-skill-library-distribution.md): the distribution design and its status.
