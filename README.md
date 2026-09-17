# .github

Default community health files, GitHub configuration, and repository management
tools for repositories owned by `f2calv`.

## Copilot customizations

`instructions/` is the single source of truth for the shared Copilot instruction
files used by every `f2calv` repository. Link it into the VS Code user profile
once and the instructions apply in every workspace:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.copilot" | Out-Null
New-Item -ItemType Junction `
  -Path "$HOME\.copilot\instructions" `
  -Target "$HOME\source\github\.github\instructions"
```

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
./.scripts/Set-RepositoryBaseline.ps1 -Repository f2calv/example -Mode Audit
```

Apply the baseline to one repository:

```powershell
./.scripts/Set-RepositoryBaseline.ps1 -Repository f2calv/example -Mode Apply
```

Audit or repair every active, owned, non-fork repository:

```powershell
./.scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Audit
./.scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Apply -WhatIf
./.scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Apply
```

The full baseline is defined in
[`repository-baseline.json`](.scripts/repository-baseline.json).

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
