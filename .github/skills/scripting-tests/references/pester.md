# Pester

How to write and run Pester 5 tests for PowerShell scripts. The always-on rules are in the
[PowerShell instructions](../../../instructions/shell.powershell.instructions.md#testing).

## Layout

- Name test files `<ScriptName>.Tests.ps1` in an adjacent `tests/` directory, and start each with
  `#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }`.
- Provide an `Invoke-Tests.ps1` entry point for a script package or skill with several tests. Pin
  its Pester import to 5.7.1 and return a non-zero exit code when tests fail.
- Keep the script's entry point behind `if ($MyInvocation.InvocationName -ne '.')` so a test can
  dot-source its functions without running the main operation.

## Writing Tests

- Test success, validation failure, external-command failure, `-WhatIf`, and idempotent or no-change
  paths where they exist. For scripts that mutate files or remote state, verify the exact changed
  surface and the rollback or no-partial-write behaviour.
- Use `$TestDrive` for files and temporary Git repositories. Never load real local configuration,
  credentials, repository coordinates or deployment identifiers into a fixture or test output.
- Build fixture paths with `Join-Path` so containment and link checks exercise the same scenario on
  Windows and Unix; use literal separators only when testing that separator's handling.
- Mock PowerShell commands with `Mock`. Wrap native executables behind functions, or place
  synthetic executables earlier on `PATH`, so tests never contact services or mutate real state.
- Write a pass-through wrapper for a native executable without `param()` or `[CmdletBinding()]`,
  forwarding `$args`; otherwise native flags such as `git add -A` bind as PowerShell parameters.
- Compare text read from files after normalising `` "`r`n" `` to `` "`n" `` on both sides:
  `ConvertTo-Json` and `Set-Content` write the platform newline, so a committed LF fixture differs
  from Windows output.
- In data-driven `-ForEach` blocks, Pester expands `<Name>` in titles at run time, so a name filter
  does not match them; check the executed test count rather than trusting a zero-test success.

## Running

Import the pinned version before invoking, so auto-loading never picks another installed Pester:

```powershell
Import-Module Pester -RequiredVersion 5.7.1
$Configuration = New-PesterConfiguration
$Configuration.Run.Path = './scripts/tests'
$Configuration.Run.PassThru = $true
$Result = Invoke-Pester -Configuration $Configuration
'{0} passed, {1} failed' -f $Result.PassedCount, $Result.FailedCount
```

Before pushing, run through the repository's `Invoke-Tests.ps1` when it has one, because CI does:
a runner that sets `Set-StrictMode -Version 3.0` imposes it on every script and module the tests
call, so code such as indexing `[0]` into an empty result passes a bare `Invoke-Pester` and fails
in CI. On Windows, call it with `pwsh -Command "& ./Invoke-Tests.ps1 -TestPath @('a', 'b')"`;
`pwsh -File` does not pass an array parameter.

## Continuous Integration

Install the pinned module in the job, then run the suite through its runner:

```yaml
- name: Install-Module Pester -RequiredVersion 5.7.1
  shell: pwsh
  run: Install-Module Pester -Scope CurrentUser -RequiredVersion 5.7.1 -Force
```
