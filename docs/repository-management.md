# Repository Management

PowerShell tools in the [repository baseline skill](../.github/skills/github-repository-baseline/SKILL.md)
audit and create GitHub repositories with consistent settings. Run the examples from this
repository's root. They require PowerShell 7.4 or later, Git and an authenticated GitHub CLI account
with the permissions the operation needs.

## Audit Settings

Audit one repository without changing remote settings:

```powershell
.\.github\skills\github-repository-baseline\scripts\Set-RepositoryBaseline.ps1 `
  -Repository owner/example `
  -Mode Audit
```

Preview changes for the same repository:

```powershell
.\.github\skills\github-repository-baseline\scripts\Set-RepositoryBaseline.ps1 `
  -Repository owner/example `
  -Mode Apply `
  -WhatIf
```

The [baseline policies](../.github/skills/github-repository-baseline/scripts/policies/) define the
settings: `<owner>.json` when present for the target owner, otherwise the generic `default.json`.
Follow the [baseline workflow](../.github/skills/github-repository-baseline/SKILL.md) before
applying changes; unavailable plan-dependent capabilities are reported rather than bypassed.

## Create a Repository

The [repository creation script](../.github/skills/github-repository-baseline/scripts/New-GitHubRepository.ps1)
creates a GitHub repository, applies the baseline and clones it locally. Choose visibility
explicitly; the script defaults to public visibility.

```powershell
.\.github\skills\github-repository-baseline\scripts\New-GitHubRepository.ps1 `
  -Name example `
  -Description 'Example repository' `
  -Visibility Private
```

Use `-TemplateRepository owner/template` to start from a template, `-NoClone` to omit the local
clone, or `-AddToWorkspace` to add it to the active VS Code workspace. The owner defaults to the
authenticated GitHub account.

## GitHub Community Defaults

GitHub uses this public account-level repository's defaults for owned public **and** private
repositories that do not supply their own corresponding files:

- [Issue forms](../.github/ISSUE_TEMPLATE/) for bugs, feature requests and support.
- [Pull request template](../.github/pull_request_template.md) for scope, issue links and validation.
- [Contribution guidance](../CONTRIBUTING.md) and [support guidance](../SUPPORT.md).

These defaults are a GitHub feature, independent of the Copilot setup, and do not need copying into
consumer repositories. A repository's own issue-template configuration overrides the default
issue-template directory as a whole; consult
[GitHub's inheritance rules](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)
before adding local overrides.
