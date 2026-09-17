# Copilot Instructions

This repository is the single source of truth for every reusable Copilot customization used across `f2calv` repositories — instruction files today, agent skills and custom agents later.

Individual repositories no longer carry a `.github/instructions/` folder. They keep only their own `.github/copilot-instructions.md`, which points here and holds that repository's specific rules.

## Setup

The canonical instruction files live in `instructions/`, reusable skills in `skills/`, and shared
slash-command prompts in `prompts/`.
Link both folders into the VS Code user profile so they apply in **every** workspace, whether or not
this repository is open:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.copilot" | Out-Null
New-Item -ItemType Junction `
  -Path "$HOME\.copilot\instructions" `
  -Target "$HOME\source\github\.github\instructions"
New-Item -ItemType Junction `
  -Path "$HOME\.copilot\skills" `
  -Target "$HOME\source\github\.github\skills"
New-Item -ItemType Junction `
  -Path "$HOME\.copilot\prompts" `
  -Target "$HOME\source\github\.github\prompts"
```

Confirm the link resolves and VS Code can see the files:

```powershell
Get-Item "$HOME\.copilot\instructions" | Select-Object LinkType, Target
Get-Item "$HOME\.copilot\skills" | Select-Object LinkType, Target
Get-ChildItem "$HOME\.copilot\instructions" -Filter *.instructions.md | Measure-Object
Get-ChildItem "$HOME\.copilot\skills" -Filter SKILL.md -Recurse | Measure-Object
```

In VS Code, open the Chat view, select **Diagnostics** from the context menu, and check the files are listed as user-level instructions.

Notes:

- User-profile instructions apply across all workspaces and take **priority over** repository instructions. A repository that needs to override a central rule must say so explicitly in its own `copilot-instructions.md`.
- A junction points at the working tree, so a `git pull` here updates every workspace immediately. There is nothing to sync and no pull requests to raise.
- Because the files are not copied into other repositories, an instructions change never triggers their continuous integration or bumps their version.
- Skills live in `skills/`, linked to `~/.copilot/skills`, and prompts in `prompts/`, linked to `~/.copilot/prompts`. Both are kept at the repository root for the same reason as `instructions/` — a folder under `.github/` would also be discovered as a workspace customisation whenever this repository is open, loading everything twice. Agents will follow the same pattern.
- Enable Settings Sync to carry user-level customizations to another device, or create the junction there too.

## Layout

| Path | Purpose |
| --- | --- |
| `instructions/` | Canonical `*.instructions.md` files, linked into `~/.copilot/instructions` |
| `skills/` | Reusable agent skills, linked into `~/.copilot/skills` |
| `prompts/` | Shared slash-command prompts, linked into `~/.copilot/prompts` |
| `.scripts/` | Repository management, baseline and privacy tooling |
| `.github/` | This repository's own Copilot and GitHub configuration |

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
