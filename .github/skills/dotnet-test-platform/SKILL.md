---
name: dotnet-test-platform
description: 'Configure, migrate, or troubleshoot .NET tests on Microsoft.Testing.Platform and xUnit v3: global.json runner selection, test project properties, VSTest package removal, dotnet test command syntax, filters, coverage, and CI workflow or VS Code task test steps.'
argument-hint: '[scope=repository|workflow] [mode={audit|migrate|update}]'
user-invocable: true
---

# .NET Test Platform

Every .NET repository is forward-only on `Microsoft.Testing.Platform` (MTP) with xUnit v3. Use this
workflow when adding the first test project, migrating from VSTest, or authoring `dotnet test` steps
in workflows, composite actions or `.vscode/tasks.json`. Test structure, naming and assertion rules
remain in the shared testing instructions.

Never run tests without explicit user approval; they may be integration tests needing credentials
or external services.

## Required Configuration

- Select MTP in the root `global.json` of every .NET repository, including repositories without
  tests yet, so the first test project is MTP-native rather than silently inheriting VSTest:

  ```json
  {
      "test": {
          "runner": "Microsoft.Testing.Platform"
      }
  }
  ```

- Reference `xunit.v3` and, when coverage is required, `Microsoft.Testing.Extensions.CodeCoverage`.
  Remove `xunit`, `xunit.runner.visualstudio`, `Microsoft.NET.Test.Sdk`, `coverlet.collector` and
  other VSTest-era packages.
- Configure xUnit v3 test projects as MTP executables with `OutputType=Exe`, `IsTestProject=true`,
  `UseMicrosoftTestingPlatformRunner=true` and `TestingPlatformDotnetTestSupport=true`.

## Command Syntax

- Use the .NET 10 native command: `dotnet test --project <path.csproj>` or
  `dotnet test --solution <path.slnx>`. Never pass a project or solution as a bare positional
  argument, and do not use `dotnet run` as the normal test command.
- Pass MTP and xUnit v3 arguments directly, without the legacy `--` separator. Use `--filter-class`,
  `--filter-method`, `--filter-trait`, `--filter-not-trait`, `--coverage` and
  `--coverage-output-format cobertura`. Never use VSTest `--filter`, `--collect`, `--logger` or
  coverlet MSBuild properties.

## Workflows and Actions

- Shared workflows and actions require the MTP selection and fail with an actionable error when it
  is absent.
- Do not retain VSTest detection, fallback command lines or dual coverage pipelines.

## Migration Workflow

1. Inventory `global.json`, every test project, `Directory.Packages.props`, workflows, composite
   actions and `.vscode/tasks.json` for VSTest packages, properties and command lines.
2. Add the `global.json` runner selection, swap packages centrally and set the project properties.
3. Rewrite every command line to the native syntax above, including filters and coverage.
4. Before changing runners, verify console-output visibility and `ITestOutputHelper` behaviour
   against the repository's exact SDK, xUnit and test-platform versions. Quiet output is easily
   misread as no execution. Do not remove `ITestOutputHelper` or swap runners on the strength of an
   unverified limitation.
5. With approval, run the suite and record the commands, verbosity, discovered-test counts,
   passed/failed/skipped totals and observed output behaviour.

## Reporting

Report the files changed, packages removed and added, command lines rewritten, and the recorded
test evidence, listing any checks not run.
