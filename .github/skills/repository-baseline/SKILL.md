---
name: repository-baseline
description: 'Audit, preview, apply, and verify consistent GitHub repository settings and default-branch rulesets. Use when standardizing repositories, migrating classic branch protection, checking baseline drift, creating a repository, or troubleshooting PlanGated and partial fleet runs.'
argument-hint: '[repositories=owner/name,... | all-owned] [mode={audit|whatif|apply|create}]'
user-invocable: true
---

# Repository Baseline

Standardize GitHub repository settings through the policy and PowerShell tools bundled with this
skill. Use the scripts as the implementation authority and this document as the operational runbook.

## Prerequisites

- PowerShell 7.4 or later.
- GitHub CLI authenticated with repository administration access.
- Pester 5.7.1 only when changing the scripts or policy.
- A clean understanding of which repositories are in scope. Never infer private repository names for
  public output.

## Safety Model

- `Audit` is read-only and may run directly.
- `Apply -WhatIf` is read-only and must precede every real apply.
- `Apply` changes remote GitHub settings. Obtain explicit user approval for the requested scope.
- Pilot changes on a small representative set before a fleet-wide apply.
- Capture and compare the relevant remote state before and after a pilot.
- Never replace or delete unrelated custom rulesets. The reconciler migrates only canonical or named
  historical baseline rulesets.
- Never delete classic branch protection until the replacement ruleset has been fetched and verified.
- Treat `PlanGated` as an expected capability result, not as permission to bypass the unavailable
  protection.
- Public repositories require the `SonarCloud Code Analysis` check before their default branch can
  be updated through a pull request. Private repositories do not inherit this cloud check.
- Never persist credentials or include private repository identities in public issues, commits, logs,
  or examples.

## Assets

| Asset | Purpose |
| --- | --- |
| [Set-RepositoryBaseline.ps1](./scripts/Set-RepositoryBaseline.ps1) | Audit and reconcile one, several, or all owned repositories |
| [repository-baseline.json](./scripts/repository-baseline.json) | Declarative repository and ruleset policy |
| [Invoke-Tests.ps1](./scripts/Invoke-Tests.ps1) | Run the Pester regression suite after policy or script changes |

## Parameters

### Baseline reconciler

| Parameter | Meaning |
| --- | --- |
| `-Repository owner/name,...` | One or more explicit repositories |
| `-AllOwned` | Every active, owned, non-fork repository |
| `-Mode Audit` | Report drift without mutation |
| `-Mode Apply -WhatIf` | Preview reconciliation without mutation |
| `-Mode Apply` | Reconcile remote settings |
| `-PolicyPath <path>` | Override the bundled JSON policy |
| `-OutputPath <path>` | Write detailed structured results locally |

Use exactly one of `-Repository` and `-AllOwned`.

## Runbook

### 1. Establish Scope

1. Resolve explicit repository names from the request, or confirm that all active owned repositories
   are intended.
2. Exclude forks, archived repositories, and disabled repositories from fleet operations.
3. Identify representative pilot shapes:
   - classic branch protection;
   - a named historical ruleset;
   - a repository with a policy override, such as required status checks;
   - a plan-gated private repository when capability reporting needs validation.

### 2. Audit

Run an explicit repository audit:

```powershell
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 `
  -Repository owner/example `
  -Mode Audit
```

Or audit the fleet:

```powershell
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 `
  -AllOwned `
  -Mode Audit
```

Interpret each setting independently:

- `Compliant`: no change required.
- `Drift`: policy and remote state differ.
- `PlanGated`: unavailable on the current GitHub plan or repository visibility.
- `Failed`: an API, authentication, validation, or unsupported-shape failure requiring investigation.

Do not proceed from an unexplained `Failed` result.

### 3. Preview

Preview exactly the intended scope:

```powershell
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 `
  -Repository owner/example,owner/example-module `
  -Mode Apply `
  -WhatIf
```

For high-impact changes, fingerprint rulesets and classic protection before and after the preview and
confirm the fingerprints are identical.

### 4. Apply a Pilot

After explicit approval, apply only to the representative repositories:

```powershell
./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 `
  -Repository owner/example,owner/example-module `
  -Mode Apply
```

If a batch reports a repository-level failure:

1. Audit each pilot repository separately with `-OutputPath` to identify the failed target.
2. Verify whether the failure occurred before mutation or during reconciliation.
3. Do not rerun repositories already reported compliant.
4. Retry only the failed repository after understanding the failure.

### 5. Verify the Pilot

1. Rerun `Audit`; every supported setting must report `Compliant`.
2. Fetch the detailed ruleset.
3. Verify the canonical name and expected rule types and parameters.
4. Verify repository-specific policy overrides are retained.
5. Verify `SonarCloud Code Analysis` is required on public repositories only.
6. Verify stale status checks are absent.
7. Verify classic protection is absent after migration.
8. Run a second audit to prove idempotency.

### 6. Apply the Fleet

Only after the pilot passes:

1. Run `-AllOwned -Mode Apply -WhatIf`.
2. Review counts for `WhatIf`, `Compliant`, `PlanGated`, and `Failed`.
3. Obtain explicit approval for fleet mutation.
4. Run `-AllOwned -Mode Apply`.
5. Run `-AllOwned -Mode Audit` as the authoritative second pass.
6. Independently sample or enumerate rulesets to verify the exact post-state.

### 7. Report

Report:

- pilot repositories and migration shapes;
- changed, compliant, plan-gated, and failed counts;
- canonical ruleset count;
- remaining classic-protection count;
- policy overrides retained;
- final audit exit code;
- any retry or follow-up required.

Do not publish private repository identities or infrastructure details in a public report.

## Changing the Policy or Scripts

1. Update [repository-baseline.json](./scripts/repository-baseline.json) as the source of truth.
2. Add Pester coverage in the bundled `scripts/tests/` directory alongside every behavior change.
3. Cover compliant, drifted, plan-gated, failed, `WhatIf`, idempotent, and missing-property cases.
4. Preserve repository-specific required checks and merge visibility-wide checks into the same
  `required_status_checks` rule; GitHub rulesets must not receive duplicate rules of that type.
5. Ask before running the Pester suite when local workflow instructions require confirmation.
6. Run static analysis, Markdown validation, a live read-only audit, and a fleet `WhatIf` before apply.

From this repository, the regression suite entry point is:

```powershell
npm run test:ps
```

## New Repository Setup

Use the repository helper from the central customization checkout:

```powershell
./.scripts/New-GitHubRepository.ps1 `
  -Name example `
  -Description 'Example repository'
```

The helper creates or resumes the repository, invokes the bundled baseline reconciler, clones it, and
can add it to the active VS Code workspace.

## Troubleshooting

| Symptom | Response |
| --- | --- |
| `PlanGated` | Record the unsupported capability; do not emulate or bypass it |
| Repository-level API failure | Audit that repository alone and retry only after identifying the failed stage |
| Verification failure | Confirm classic protection was retained; inspect the returned ruleset body |
| Historical ruleset remains | Confirm its name and rule types are recognized by policy before migration |
| Custom ruleset exists | Preserve it; create or update only the policy-owned canonical ruleset |
| Unexpected status checks | Compare the repository name with policy override patterns |
| `WhatIf` changes fingerprints | Stop; treat as a script defect before any apply |
| Fleet audit exits nonzero | Inspect `Drift` and `Failed`; `PlanGated` alone is non-blocking |
