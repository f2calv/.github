# .github

Default community health files, GitHub configuration, and repository management
tools for repositories owned by `f2calv`.

## Copilot customizations

`.github/instructions/`, `.github/skills/` and `.github/prompts/` hold shared Copilot instructions,
reusable skills and slash-command prompts. They are the single source of truth: no repository keeps
its own copy, so a change here takes effect everywhere with no pull requests and no version bumps.

VS Code discovers customizations from two places, which gives you two ways to use this repository.
Pick whichever suits you — they are interchangeable, and you can switch later.

### Option 1 — Add this repository to your workspace (no setup)

VS Code reads customizations from `<folder>/.github/…` for **every folder open in the workspace**.
So cloning this repository next to your own and opening both together is enough:

1. Clone this repository alongside the repository you are working in.
2. In VS Code, open your own repository, then **File → Add Folder to Workspace…** and add this one.
3. **File → Save Workspace As…** so the pairing persists.

The instructions, skills and prompts apply immediately. Nothing to install, no shell, no admin
rights. The trade-off is that they apply only inside that workspace.

### Option 2 — Link into your user profile (applies everywhere)

VS Code also reads customizations from `~/.copilot/…`, which applies to **every** workspace whether
or not this repository is open. Create one link per folder.

Windows (PowerShell):

```powershell
$repo = "$HOME\source\github\.github"      # adjust to wherever you cloned it
New-Item -ItemType Directory -Force -Path "$HOME\.copilot" | Out-Null
foreach ($name in 'instructions', 'skills', 'prompts') {
  New-Item -ItemType Junction -Path "$HOME\.copilot\$name" -Target "$repo\.github\$name"
}
```

macOS and Linux:

```bash
repo="$HOME/source/github/.github"          # adjust to wherever you cloned it
mkdir -p "$HOME/.copilot"
for name in instructions skills prompts; do
  ln -s "$repo/.github/$name" "$HOME/.copilot/$name"
done
```

Windows without PowerShell (Command Prompt, run as Administrator or with Developer Mode enabled):

```bat
mklink /D "%USERPROFILE%\.copilot\instructions" "%USERPROFILE%\source\github\.github\.github\instructions"
mklink /D "%USERPROFILE%\.copilot\skills"       "%USERPROFILE%\source\github\.github\.github\skills"
mklink /D "%USERPROFILE%\.copilot\prompts"      "%USERPROFILE%\source\github\.github\.github\prompts"
```

A link points at the working tree, so `git pull` here updates every workspace immediately.

### Verify it worked

In VS Code, open the Chat view, choose **Diagnostics** from the context menu, and confirm the
instruction files are listed. Or check from a shell:

```powershell
Get-ChildItem "$HOME\.copilot\instructions" -Filter *.instructions.md | Measure-Object
Get-ChildItem "$HOME\.copilot\skills" -Filter SKILL.md -Recurse | Measure-Object
Get-ChildItem "$HOME\.copilot\prompts" -Filter *.prompt.md | Measure-Object
```

### If you use both options at once

Using Option 2 *and* keeping this repository in your workspace means the same files are discovered
twice — once as a user-level customization and once as a workspace one. It is harmless, but it
duplicates the rules in context and clutters the diagnostics view. If that bothers you, remove this
repository from the workspace and open it in a separate window when you want to edit it.

### What these files are

| Folder | Contents | Applies |
| --- | --- | --- |
| `.github/instructions/` | `*.instructions.md` | Automatically, per the `applyTo` glob in each file |
| `.github/skills/` | `<name>/SKILL.md` | When the task matches the skill's description |
| `.github/prompts/` | `*.prompt.md` | When invoked as a slash command |

This repository's own `.github/copilot-instructions.md` applies only here and is not part of the
shared set.

Setup details, authoring rules, and what each repository keeps locally are in
[`copilot-instructions.md`](.github/copilot-instructions.md).

## Repository baseline

The baseline enforces these settings where the GitHub plan supports them:

* Delete merged branches automatically
* Give GitHub Actions read-only default token permissions
* Prevent GitHub Actions from approving pull requests
* Enable Dependabot vulnerability alerts and security updates
* Enable secret scanning and push protection
* Protect the default branch from deletion and force pushes
* Require changes through pull requests with resolved review threads
* Require the SonarCloud Code Analysis check before merging to the default branch in analysis-ready public repositories

The default branch is managed by one canonical `f2calv repository baseline`
ruleset. Apply mode migrates equivalent historical rulesets and classic branch
protection only after the canonical ruleset has been verified. Public repositories
require `SonarCloud Code Analysis` once their imported project has produced an analysis;
repository-specific lint, versioning, build, test, and validation checks are merged into the same
status-check rule. Explicit zero-analysis exclusions and private repositories do not inherit the
SonarCloud gate.

Audit one repository without changing it:

```powershell
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 `
  -Repository f2calv/example `
  -Mode Audit
```

Apply the baseline to one repository:

```powershell
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 `
  -Repository f2calv/example `
  -Mode Apply
```

Audit or repair every active, owned, non-fork repository:

```powershell
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Audit
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Apply -WhatIf
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Apply
```

The full baseline is defined in
[`repository-baseline.json`](skills/repository-baseline/scripts/repository-baseline.json).

The complete audit, pilot, apply, verification, and recovery workflow is packaged
as the [`repository-baseline` skill](skills/repository-baseline/SKILL.md).

Run the PowerShell regression suite through npm:

```powershell
Install-Module Pester -Scope CurrentUser -RequiredVersion 5.7.1
npm run test:ps
```

## .NET release train

The [`dotnet-release-train` skill](.github/skills/dotnet-release-train/SKILL.md) coordinates
dependency-ordered package releases across the .NET repositories open in the current workspace. It
follows a repeatable per-repository checklist: update compatible packages, validate Debug and
Release paths, merge the pull request, verify every package on NuGet, and continue with its direct
consumers.

Start at the first producer that needs updating:

```text
/dotnet-release-train
/dotnet-release-train start=CasCap.Api.GooglePhotos
```

Run the helper regression suite through npm:

```powershell
npm run test:release-train
```

## Create a repository

Create, configure, and clone a public repository:

```powershell
./.scripts/New-GitHubRepository.ps1 `
  -Name example `
  -Description 'Example repository'
```

Create from a template and add the clone to the active VS Code workspace:

```powershell
./.scripts/New-GitHubRepository.ps1 `
  -Name example `
  -TemplateRepository f2calv/template-dotnet `
  -AddToWorkspace
```

Use `-Visibility Private` for private repositories. Secret protection and
default-branch rulesets are reported as plan-gated when they are unavailable.
