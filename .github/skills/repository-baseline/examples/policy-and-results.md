# Policy Override and Partial Results

Use the existing [default policy](../scripts/policies/default.json) as the base, not a copied
baseline maintained inside this example. The
[required-checks fragment](../templates/required-checks.override.json) is one `rulesetOverrides`
array item, **not a complete policy** accepted by `-PolicyPath`.

## Build the Local Policy

In an approved local output directory, load the default and attach the synthetic override:

```powershell
$central = '<absolute-central-checkout>'
$output = '<absolute-local-policy-path>'
$skill = Join-Path $central '.github/skills/repository-baseline'
$policy = Get-Content -LiteralPath (Join-Path $skill 'scripts/policies/default.json') -Raw |
    ConvertFrom-Json
$override = Get-Content -LiteralPath (Join-Path $skill 'templates/required-checks.override.json') -Raw |
    ConvertFrom-Json
$policy.rulesetOverrides = @($override)
$policy | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $output -Encoding utf8
```

This creates a new policy from the default. For an existing owner policy, merge the intended item
instead of replacing its override array. Replace `owner/example` with an explicitly scoped target
only after resolving repository visibility, and keep private coordinates in a local policy.
The match is exact in this fragment; do not broaden it to `owner/*` for convenience.

The two check names are illustrative. Verify exact check contexts emitted by the target's current
workflow, including reusable-job prefixes, before making either required. A required check that
never reports blocks merges. This example does not change merge methods or disable other rules.

`publicRepository.requiredStatusChecks` remains owned by the policy's existing visibility-wide
contract. The reconciler merges such public checks with matching repository overrides into one
`required_status_checks` rule. Private repositories do not inherit the public list, but a matching
repository override still applies. Never remove an expected analysis gate just to make the example
work.

## Audit and Preview Are Separate

From the central repository root, after authorizing the intended GitHub reads:

```powershell
./.github/skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 `
    -Repository owner/example -PolicyPath $output -Mode Audit
./.github/skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 `
    -Repository owner/example -PolicyPath $output -Mode Apply -WhatIf
```

These commands contact GitHub; they are not offline validation. An actual `Apply` without
`-WhatIf` needs separate mutation approval after the preview and pilot gates. The example tests
invoke only pure policy composition or mocked APIs.

`-OutputPath` is an optional local report write, even in Audit mode. Under `-WhatIf`, that write
is also suppressed by `ShouldProcess`; do not expect a preview JSON file to exist. Neither command
creates a PR, commits changes, or authorizes a fleet-wide apply.

## Interpret Partial Success

[The synthetic result array](./partial-results.json) uses the implementation's exact four fields:
`Repository`, `Setting`, `Status`, `Detail`. It is an excerpt of an Apply result, not a full live audit.

| Status | Meaning | Next action |
| --- | --- | --- |
| `Compliant` | That setting matched at inspection time | Preserve it; do not infer other settings passed |
| `Changed` | A mutation returned success | Re-audit and independently verify the resulting state |
| `Drift` | Audit found a mismatch | Preview the specific intended correction |
| `WhatIf` | A mutation was proposed, not performed | Review scope and obtain approval |
| `PlanGated` | The control is unavailable for the plan/capability | Record the unprotected capability; never call it enforced |
| `Failed` | An operation or verification failed | Stop that target, inspect current state and retry only after diagnosis |

For the supplied five-row excerpt: two settings are Compliant, one Changed, one PlanGated and one
Failed. The command's blocking-status rule is `Drift` or `Failed`, so this result must exit nonzero.
PlanGated alone is non-blocking to the script but can still violate the operator's required
protection policy. Do not summarize this excerpt as "two repositories passed" or count setting rows
as repositories.

A suitable handoff is: "Partial apply; one setting changed, one capability unavailable, and one
ruleset fetch failed. Re-audit the affected target and verify its actual ruleset/classic-protection
state before retrying. No fleet-compliance claim." Do not assume rollback occurred or classic
protection was retained solely from a generic API failure message.

Reports can contain private repository identities and API details. Keep real report files local,
review any public summary independently, and never copy raw `Detail` fields into public issues.
