# .github

Default community health files, GitHub configuration, and repository management
tools for repositories owned by `f2calv`.

## Copilot customizations

`instructions/`, `skills/` and `prompts/` are the single source of truth for shared Copilot
instructions, reusable skills and slash-command prompts. Link them into the VS Code user
profile once and they apply in every workspace:

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

Verify the links resolve and the files are visible through them:

```powershell
Get-Item "$HOME\.copilot\instructions", "$HOME\.copilot\skills", "$HOME\.copilot\prompts" |
  Select-Object Name, LinkType, Target
Get-ChildItem "$HOME\.copilot\instructions" -Filter *.instructions.md | Measure-Object
Get-ChildItem "$HOME\.copilot\skills" -Filter SKILL.md -Recurse | Measure-Object
Get-ChildItem "$HOME\.copilot\prompts" -Filter *.prompt.md | Measure-Object
```

A junction points at the working tree, so a `git pull` here updates every workspace
immediately. Nothing is copied into other repositories, so an instructions change never
triggers their continuous integration or bumps their version.

### Why these folders sit at the repository root

`instructions/`, `skills/` and `prompts/` are deliberately **not** under `.github/`.

VS Code discovers customizations from two independent places: the user profile
(`~/.copilot/…`, where the junctions point) and every folder open in the workspace
(`<folder>/.github/instructions/`, `<folder>/.github/skills/` and `<folder>/.github/prompts/`). Putting the canonical
files under this repository's own `.github/` would satisfy both rules at once — so
whenever this repository is open in a workspace, every instruction file and skill would be
discovered twice, once as a user-level customization and once as a workspace one.

That wastes context on duplicated rules and makes the diagnostics view hard to read. Keeping
the canonical copies at the repository root means the junctions are the only discovery path,
and the files load exactly once no matter which repositories are open.

This repository's own `.github/copilot-instructions.md` is a separate file that applies only
here, and is unaffected.

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

The default branch is managed by one canonical `f2calv repository baseline`
ruleset. Apply mode migrates equivalent historical rulesets and classic branch
protection only after the canonical ruleset has been verified. Terraform module
repositories additionally require the standard lint, versioning, and Terraform
validation checks; stale status checks on other repositories are removed.

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
