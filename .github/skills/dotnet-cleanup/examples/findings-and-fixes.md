# Cleanup Findings, Fixes and Boundaries

These synthetic snippets demonstrate the existing audit and logging fixer. They are source-analysis
fixtures, not a complete application or permission to rename public contracts.

## Layout Findings

### `Widget.cs` before

```csharp
namespace Example;

public sealed class Widget { }
public sealed class WidgetOptions { }
```

The layout audit reports `OneTopLevelTypePerFile`. Keep `Widget` in its file and move
`WidgetOptions` to its matching file under the owning project's Models folder/namespace, updating
references through the language tooling. Preserve history with a move before editing when an
existing file itself is being renamed. Do not rename a published type merely to match a bad filename.

### `Widget.cs` after

```csharp
namespace Example;

public sealed class Widget { }
```

### `Models/WidgetOptions.cs` after

```csharp
namespace Example.Models;

public sealed class WidgetOptions { }
```

The empty types isolate the layout rule; do not add empty production types to follow the example.
The audit does not check namespace/folder placement, compile references, or compatibility.
A clean layout report alone cannot prove the move is correct.

## Valid Exceptions and False-Positive Review

| Source shape | Intended action |
| --- | --- |
| Nested private fake inside its test class | Keep it together; nested types are not extra top-level types |
| `_Enums.cs` containing enums only | Keep the allowed aggregate |
| `_WidgetConfig.cs` grouping its configuration root and related records | Keep only genuinely related configuration types |
| `Cache{TKey,TValue}.cs` for a generic type | Keep the generic filename convention |
| `Worker.Logging.cs` declaring a partial `Worker` | Keep the partial suffix; do not rename the type to match the whole stem |
| Traditional constructor with a reported candidate | Inspect initialization, accessibility and overloads before converting |
| Lowercase external wire-contract member | Check serialization/public compatibility before renaming; do not treat a regex finding as authorization |

The existing layout regressions exercise nested types, aggregate exceptions and partial/generic
filenames. Reuse those tests rather than creating a parallel rule catalogue or parser.
When a finding is wrong, preserve a minimal regression in the owning audit suite and fix the
detector; do not suppress all findings from that area.

## Logging: A Narrow Mechanical Change

### Logging before

```csharp
if (logger.IsEnabled(LogLevel.Information))
    logger.LogInformation("{ClassName} processed {itemCount} items in {elapsedMs:0.0} ms",
        nameof(ImportService), itemCount, elapsedMs);
```

### Logging after

```csharp
if (logger.IsEnabled(LogLevel.Information))
    logger.LogInformation("{ClassName} processed {ItemCount} items in {ElapsedMs:0.0} ms",
        nameof(ImportService), itemCount, elapsedMs);
```

Only template property casing changes. Argument order, C# variable names, format specifier,
message wording and level remain unchanged. These bounded counts contain no user content.
Structured-property casing can affect log queries and dashboards: inspect consumers before applying
the change. A hot loop should use the shared source-generated logging pattern in a separate,
measured change instead of treating this casing repair as a performance conversion.

### Interpolated logging is not automatically repaired

```csharp
logger.LogInformation($"Processed {itemCount} items");
```

The fixer deliberately skips interpolation; this snippet is an anti-pattern requiring manual
structured-logging conversion, not an acceptable result because the casing check reports no edits.
It also does not migrate source-generated attributes or multiline templates.

## Invoke the Existing Tools

From the central checkout, using an explicit target repository:

```powershell
$repository = '<absolute-target-repository>'
./.github/skills/dotnet-cleanup/scripts/Test-DotNetSourceConventions.ps1 -RepositoryPath $repository -Audit Layout
./.github/skills/dotnet-cleanup/scripts/Set-DotNetLogTemplateCasing.ps1 -RepositoryPath $repository -WhatIf
./.github/skills/dotnet-cleanup/scripts/Set-DotNetLogTemplateCasing.ps1 -RepositoryPath $repository -Check
```

The target audit/fixer enumerates tracked C# source. A newly created, untracked file is not proof
of coverage. Preserve unrelated edits and inspect the exact candidate files before running the
fixer without `-WhatIf`/`-Check`; `-Check` is a gate, not a write.

After an approved fix, require the exact before/after change, rerun the same check and prove a
second fix produces no edits. Compile affected consumers and run approved focused tests when
changing real source. Formatting routes remain separate: use `style` for IDE diagnostics and
`analyzers` for CA diagnostics through the existing formatter helper, not a solution-wide fix.
