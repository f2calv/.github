# Copilot Instructions

This repository is the single source of truth for every reusable Copilot customization used across `f2calv` repositories — instruction files today, agent skills and custom agents later.

Individual repositories no longer carry a `.github/instructions/` folder. They keep only their own `.github/copilot-instructions.md`, which points here and holds that repository's specific rules.

## Setup

The shared files live under `.github/instructions/`, `.github/skills/` and `.github/prompts/`, the
locations VS Code reads for any folder open in a workspace. There are two ways to consume them, set
out for end users in the [README](../README.md):

- **Add this repository to the workspace** alongside the repository being worked on. No setup, but it
  applies only inside that workspace.
- **Link the folders into the user profile** so they apply in every workspace:

```powershell
$repo = "$HOME\source\github\.github"
New-Item -ItemType Directory -Force -Path "$HOME\.copilot" | Out-Null
foreach ($name in 'instructions', 'skills', 'prompts') {
  New-Item -ItemType Junction -Path "$HOME\.copilot\$name" -Target "$repo\.github\$name"
}
```

Confirm VS Code can see them:

```powershell
Get-ChildItem "$HOME\.copilot\instructions" -Filter *.instructions.md | Measure-Object
Get-ChildItem "$HOME\.copilot\skills" -Filter SKILL.md -Recurse | Measure-Object
Get-ChildItem "$HOME\.copilot\prompts" -Filter *.prompt.md | Measure-Object
```

In VS Code, open the Chat view, select **Diagnostics** from the context menu, and check the files are listed.

Notes:

- User-profile customizations apply across all workspaces and take **priority over** repository instructions. A repository that needs to override a central rule must say so explicitly in its own `copilot-instructions.md`.
- A link points at the working tree, so a `git pull` here updates every workspace immediately. There is nothing to sync and no pull requests to raise.
- Because the files are not copied into other repositories, an instructions change never triggers their continuous integration or bumps their version.
- Using both options at once discovers every file twice, once per route. It is harmless but duplicates rules in context; remove this repository from the workspace if that matters.
- Enable Settings Sync to carry user-level customizations to another device, or create the links there too.

## Layout

| Path | Purpose |
| --- | --- |
| `.github/instructions/` | Canonical `*.instructions.md` files |
| `.github/skills/` | Reusable agent skills |
| `.github/prompts/` | Shared slash-command prompts |
| `.scripts/` | Repository management, baseline and privacy tooling |
| `.github/copilot-instructions.md` | This repository's own instructions, not part of the shared set |

## Authoring Rules

- These files are public. They must contain no personally identifiable information, no credentials, no private repository names, and no project-specific examples. Write every rule so it reads sensibly in any repository.
- Every file carries YAML frontmatter with a `description` and an `applyTo` glob. Without `applyTo` the file is never applied automatically.
- `applyTo` is matched relative to the workspace root. Prefer portable patterns such as `**/*.cs`. Avoid patterns anchored to one repository's folder layout.
- One topic per file, named `<topic>.instructions.md`. Keep rules short and self-contained, and say why a rule exists where the reason is not obvious.
- Prefer amending an existing file over adding a near-duplicate one.

## What Stays in Each Repository

A repository keeps a single `.github/copilot-instructions.md` containing:

1. A pointer to this repository for the shared instructions and skills.
2. Rules genuinely specific to that repository — its purpose, architecture, domain terminology, and any deliberate deviation from a central rule.

It must not contain a `.github/instructions/` folder or a copy of any centrally maintained file.
