# Scoped EditorConfig Override

This example exempts generated EF migrations in one synthetic project from CA1861 while keeping
the central DotNet profile's warning for ordinary source and other projects. It does not relax
the repository's warning policy or copy the central profile.

## Own the Exception in One Fragment

Copy [the narrow fragment](../templates/ef-migrations.editorconfig) to
`.config/editorconfig/overrides.editorconfig` in the consuming repository. Replace the synthetic
project path with the actual migration owner and retain the explanation beside the rule.
Do not add `root = true` to an appended fragment or hand-edit the generated root `.editorconfig`.

EditorConfig patterns are evaluated relative to the generated `.editorconfig`, **not** relative
to the fragment's storage directory. The example matches direct children of that one `Migrations`
directory; expand it deliberately if the repository generates nested migration directories.

## Preview, Generate, Check

Run from PowerShell 7.4 with the central checkout and target root explicitly selected:

```powershell
$central = '<absolute-central-checkout>'
$repository = '<absolute-target-repository>'
$generator = Join-Path $central '.github/skills/editorconfig-management/scripts/Set-EditorConfig.ps1'
$overrides = Join-Path $repository '.config/editorconfig/overrides.editorconfig'
$parameters = @{
    RepositoryPath = $repository
    Profile = 'DotNet'
    OverridePath = @($overrides)
}

& $generator @parameters -WhatIf
if ($LASTEXITCODE -ne 0) { throw 'EditorConfig preview failed.' }
& $generator @parameters
if ($LASTEXITCODE -ne 0) { throw 'EditorConfig generation failed.' }
& $generator @parameters -Check
if ($LASTEXITCODE -ne 0) { throw 'EditorConfig drift check failed.' }
```

The placeholders are local inputs, not paths to commit. The same profile **and ordered override
list** must be passed to every invocation. `-Check` does not remember how a file was generated.
Omitting `-OverridePath` later compares against a different expected policy and correctly reports drift.

Expected results on a fresh target: preview reports `Skipped` and creates no file; generation reports
`Updated`; check reports `Unchanged`. Repeating generation reports `Unchanged` without rewriting it.
Commit the repository-owned fragment and generated root together when publication is authorized.

## Why Order Matters

The generator appends base, language profile, then each override in argument order.
Within the resulting file, **the last matching value wins**, not the most specific-looking pattern:

| Source file | Last applicable CA1861 setting | Expected severity |
| --- | --- | --- |
| `src/Example.Persistence/Services/Writer.cs` | Central `[*.cs]` | `warning` |
| `src/Example.Persistence/Migrations/Initial.cs` | Appended project migration section | `none` |
| `src/Other.Persistence/Migrations/Initial.cs` | Central `[*.cs]` | `warning` |

For example, appending another `[*.cs]` section setting CA1861 to `suggestion` **after** this
migration exception would also change the migration's effective value to `suggestion`.
If an explicitly approved temporary broad relaxation is needed, place it before the narrow
exception and document its restoration condition under the skill's existing tightening procedure.
Do not ship such a broad relaxation merely to demonstrate precedence.

Nested `.editorconfig` files can introduce additional effective overrides. The generator checks
the root file's exact content; it is not an effective-policy audit of all nested files.

## Verify the Actual Scope

Use the existing generator regression suite to check preview, generation, idempotency and drift.
Then inspect effective policy for the three paths above with the repository's EditorConfig-aware
tooling. In an approved compiler fixture, place the same CA1861-triggering constant-array argument
in each path: the owner migration should be exempt, while the other two should retain the diagnostic.
Do not edit real generated migrations to manufacture a test case.

For a concrete compiler probe, put this member in a synthetic class in each of the three files:

```csharp
public static int Find(string value) =>
    Array.IndexOf(new[] { "first", "second", "third" }, value);
```

The explicit array syntax deliberately triggers CA1861 on the checked .NET 10 SDK. A collection
expression did not produce that diagnostic in the same fixture, so it is not an equivalent probe.
The shared style policy can also report IDE0300 for this intentionally old syntax: assert the exact
CA1861 file set separately rather than treating any failed build as proof of the override.
This is a diagnostic fixture, not a recommendation to introduce either pattern into production.

The existing strict build may promote warnings to errors. That is expected for the two non-exempt
files, not justification to disable CA1861 globally. Passing a root-file `-Check` alone is not proof
of analyzer enforcement, and this exception says nothing about the other diagnostics in migrations.
