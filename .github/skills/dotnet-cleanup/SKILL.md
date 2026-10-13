---
name: dotnet-cleanup
description: 'Audit and clean C#/.NET repositories for one-type-per-file layout, filename/type mismatches, identifier casing, primary-constructor candidates, ILogger template casing, and selected IDE/CA diagnostics. Use for source cleanup, convention drift, naming sweeps, or before tightening analyzers.'
argument-hint: 'mode={audit|fix-logging|format} repository=<path> [audit={Layout|Naming|Constructors|Logging}]'
user-invocable: true
compatibility: 'Requires PowerShell 7.4 and git. Formatter mode also requires the repository .NET SDK and restored projects.'
---

# .NET Cleanup

Audit and repair measured C# convention drift without mixing mechanical cleanup with behavioral
changes. The shared C# and .NET instructions remain authoritative; this skill supplies repeatable
discovery and narrowly scoped fixes.

## Modes

| Mode | Script | Behavior |
| --- | --- | --- |
| `audit` | `scripts/Test-DotNetSourceConventions.ps1` | Read-only tracked-source audit for layout, naming, constructors and logging templates |
| `fix-logging` | `scripts/Set-DotNetLogTemplateCasing.ps1` | Opt-in casing repair for single-line ILogger templates; supports `-Check` and `-WhatIf` |
| `format` | `scripts/Invoke-DotNetFormatDiagnostics.ps1` | Runs one IDE or CA diagnostic family project by project; supports `-Check` and `-WhatIf` |

## Audit Workflow

1. Resolve the explicit Git repository root. Never infer a repository by scanning parent folders.
2. Read its repository instructions and dirty-worktree state. Preserve unrelated changes.
3. Run a read-only audit first:

   ```powershell
   pwsh ./.github/skills/dotnet-cleanup/scripts/Test-DotNetSourceConventions.ps1 `
     -RepositoryPath <repository-root>
   ```

4. Use `-Audit Layout`, `Naming`, `Constructors`, or `Logging` to narrow the report.
5. Add `-FailOnFindings` only for a deliberate gate. Generated files and EF migrations are excluded
   unless `-IncludeGenerated` is supplied.
6. Group fixes by rule and ownership area. Keep structural moves separate from broad formatting.
7. Re-run the same audit, `git diff --check`, focused builds/tests with approval, then the repository
   privacy gate when public.

## Layout Contract

- One top-level type per matching file.
- Nested types may share their containing type's file.
- `_Enums.cs` may contain multiple enums and no other type kind.
- `_*Config.cs` may group a configuration root with directly related configuration types.
- Generic filenames use braces, for example `Widget{TKey,TValue}.cs`.
- Partial implementation suffixes such as `Widget.Logging.cs` match `Widget`.

The layout audit distinguishes top-level declarations from nested declarations by masked brace depth;
it does not flag nested test doubles.

## Logging Fix

Preview or gate before writing:

```powershell
pwsh ./.github/skills/dotnet-cleanup/scripts/Set-DotNetLogTemplateCasing.ps1 `
  -RepositoryPath <repository-root> -WhatIf
pwsh ./.github/skills/dotnet-cleanup/scripts/Set-DotNetLogTemplateCasing.ps1 `
  -RepositoryPath <repository-root> -Check
```

The fixer changes lowercase structured-template names only. It skips interpolated strings and never
renames C# symbols. Review every resulting template/argument pair.

## Formatter Diagnostics

Route IDE and CA diagnostics separately:

```powershell
pwsh ./.github/skills/dotnet-cleanup/scripts/Invoke-DotNetFormatDiagnostics.ps1 `
  -RepositoryPath <repository-root> -Diagnostic IDE0040 -Check
pwsh ./.github/skills/dotnet-cleanup/scripts/Invoke-DotNetFormatDiagnostics.ps1 `
  -RepositoryPath <repository-root> -Diagnostic CA1859,CA1861
```

Never run solution-wide automatic fixes. The formatter wrapper intentionally invokes each tracked
project separately to avoid multi-target rewrite conflicts.

## Boundaries

- Dead private members remain build-enforced through IDE0051/IDE0052; do not duplicate Roslyn.
- Package consolidation belongs to dependency/release workflows, not source cleanup.
- Parallel-loop triage belongs to the `dotnet-performance` skill and requires measurement.
- Regex-based audits are discovery aids. Use language-server references and compiler validation before
  renaming symbols or deleting code.

## Continuous Improvement

After each cleanup pass, update this skill when a recurring code-quality issue is not yet covered:
add or expand the narrowest reusable audit/fix script, add a synthetic Pester regression for the
new finding and its false-positive boundary, and update this workflow and coverage list in the same
change. Keep repository-specific incidents and domain rules out of the central skill.

## Tests

```powershell
pwsh ./.github/skills/dotnet-cleanup/scripts/Invoke-Tests.ps1
```

The Pester suite is pinned to 5.7.1 and covers exceptions, nested types, naming, constructors,
logging fixes, `-WhatIf`, and idempotency.
