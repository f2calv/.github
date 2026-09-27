---
description: 'Forward-only Microsoft.Testing.Platform and xUnit v3 conventions, plus test structure, credentials, naming, assertions and documentation.'
applyTo: '**/*Tests/**/*.cs,**/*Tests/**/README.md,**/*Tests*.csproj,**/global.json,**/.github/workflows/**,**/.vscode/tasks.json'
---

# C# Testing

## Forward-Only Test Platform

- Every .NET repository selects `Microsoft.Testing.Platform` in its root `global.json`, including
    repositories that do not yet contain tests. This makes the first future test project MTP-native
    rather than silently inheriting VSTest:

    ```json
    {
        "test": {
            "runner": "Microsoft.Testing.Platform"
        }
    }
    ```

- Use xUnit v3 for xUnit projects. Reference `xunit.v3` and, when coverage is required,
    `Microsoft.Testing.Extensions.CodeCoverage`. Remove `xunit`, `xunit.runner.visualstudio`,
    `Microsoft.NET.Test.Sdk`, `coverlet.collector` and other VSTest-era packages.
- Configure xUnit v3 test projects as MTP executables with `OutputType=Exe`, `IsTestProject=true`,
    `UseMicrosoftTestingPlatformRunner=true` and `TestingPlatformDotnetTestSupport=true`.
- Use the .NET 10 native test command: `dotnet test --project <path.csproj>` or
    `dotnet test --solution <path.slnx>`. Never pass a project or solution as a bare positional
    argument, and do not use `dotnet run` as the normal test command.
- Pass MTP and xUnit v3 arguments directly, without the legacy `--` separator. Use native options
    such as `--filter-class`, `--filter-method`, `--filter-trait`, `--filter-not-trait`, `--coverage`
    and `--coverage-output-format cobertura`; never use VSTest `--filter`, `--collect`, `--logger` or
    coverlet MSBuild properties.
- Shared workflows and actions must require the MTP selection and fail with an actionable error when
    it is absent. Do not retain VSTest detection, fallback command lines or dual coverage pipelines;
    this workspace is forward-only.

## Folder Structure

Organise every `*.Tests` project into subfolders by test type:

```text
Tests/
├── Unit/           # Self-contained tests: no DI container, no external services
└── Integration/    # Tests requiring DI, configuration or an external service
    └── TestBase.cs # Shared integration-test setup
```

Additional subfolders are permitted where a project has a genuinely distinct test category, but `Unit/` and `Integration/` remain the primary split.

## Unit Tests

- Place self-contained tests under `Tests/Unit/`.
- Do not inherit unit tests from an integration `TestBase`, and never let them require credentials or network access.
- Use domain-specific trait categories such as `Parsing`, `Serialization` or `Generation` — not `Unit`.
- May take `ITestOutputHelper` directly for diagnostic output.
- Prefer captured payloads stored as offline test assets over live calls, so behaviour is verified deterministically and reproducibly.

## Integration Tests

- Apply `[Trait("Category", "Integration")]` to every test that reaches configuration, credentials or an external service.
- Place them under `Tests/Integration/` and share configuration, logging and service setup through `TestBase`.
- Inherit from `TestBase(output)`, which wires up `ILoggerFactory` (routed to xUnit output), `IConfiguration` and, where needed, a DI container.
- Build configuration in a documented order: the test `appsettings` chain, then user secrets for local runs, then environment variables for CI, then any secret store the repository uses.
- Expose commonly-used services as `protected` fields on `TestBase` rather than resolving them again in each test class.
- Expose `protected ITestOutputHelper _output` on `TestBase`. Subclasses use that field directly; capturing the constructor parameter in a primary constructor while also passing it to the base is compile error **CS9107**.
- Dispose any `ServiceProvider` the fixture creates through `IDisposable` or `IAsyncDisposable`.
- Skip rather than fail when no credential is configured, so a contributor without access still gets a green credential-free run.
- Read CI credentials only from secret-backed environment variables. Never commit a credential, token, account identifier or tenant-specific name, and never write a resolved secret to test output.
- Never commit a secret to an `appsettings*.json` file to make a test pass.
- Keep integration tests read-only against the target service wherever the service supports it. Do not create, update or delete shared remote resources as a side effect of a test run.
- Perform account registration, linking or interactive authentication outside the test run. Never initiate an interactive login or a registration flow in CI.
- Exception: a lightweight integration test needing only `HttpClient` may take `ITestOutputHelper` directly without `TestBase`.
- **Do not run integration tests without explicit user approval.**

## Diagnostic Output

- Write diagnostics through `ITestOutputHelper`, or through an `ILogger` configured to route to xUnit output.
- Never use `Debug.WriteLine` or `Console.WriteLine`. The runner captures neither, so output is invisible in CI, in `dotnet test` and in the test explorer — precisely when it is needed. `Debug.WriteLine` is additionally compiled out of Release builds.
- Never call `Debugger.Break()` in a test; it hangs an unattended CI run.
- Prefer string interpolation over concatenation or composite format strings.
- Do not dump large payloads unconditionally. Emit only the values that explain a failure, and put the decisive ones in the assertion message so they survive into the failure report.

## Theory Parameterisation

- Consolidate facts that differ only by input into a single `[Theory]` with `[InlineData]`. This cuts duplication while widening coverage.
- Use `[Theory]` for the same logic across parameter combinations such as input sizes, thresholds or format types.
- Keep `[Fact]` for tests whose setup or assertions do not parameterise cleanly.

## Duplication

Test code is held to the same duplication gate as production code, and copy-pasted arrange blocks are the usual cause of a failed gate.

- When two tests differ only by input, use a `[Theory]`. When they differ only by fixture or assertion, extract a private helper on the test class taking the varying values as parameters.
- Build a new fixture from an existing one rather than restating it. A fixture varying a single dimension should delegate to a shared private builder in the same `*TestData.cs`, not repeat the object graph.
- Extract a repeated arrange block once it appears in a third test, or as soon as it exceeds a handful of lines in a second.
- Keep intent readable after extraction. Name a helper for what it asserts, such as `AssertGeneratedOutputIsAccepted`, rather than for its mechanics.

## Test Method Naming

- Name test methods after the method or feature under test, such as `UploadDocument`, `GetColumnCells` or `DetectsThresholdBreach`.
- Do not use verbose BDD-style sentence names such as `Should_Return_Column_When_Given_Valid_Input`.
- Use underscore-separated phases for lifecycle tests, such as `ItemLifecycle_CreateGetUpdateDelete` or `DefinitionLoadGenerateSerialize`.

## Assertions

- Every test must contain meaningful assertions. Never use `Assert.True(true)` or another placeholder assertion.
- Prefer specific assertions — `Assert.Equal`, `Assert.Contains`, `Assert.Single`, `Assert.NotNull`, `Assert.Null` — over a generic `Assert.True(condition)`.
- Never wrap the system under test in a `try`/`catch` that swallows the exception. A thrown exception must fail the test, or be asserted with `Assert.Throws` / `Assert.ThrowsAsync`.
- Tests that only measure performance — timing loops, a `Stopwatch`, elapsed-time output — without asserting correctness are not valid tests. Delete them, and move the measurement to a BenchmarkDotNet project if it is still wanted.

## Regression Tests for Reported Issues

- When fixing a reported issue, add a test that fails before the fix and passes after it, and name the issue in a comment on the test.
- Capture the offending input shape as an offline test asset rather than reproducing it against a live service.

## Dead Code

- Delete commented-out tests, unreachable code behind an early `return`, and permanently skipped tests rather than leaving them to rot.
- When removing the last consumer of a helper or field, remove that helper or field in the same commit.
- Clean up `using` directives that become unused after a test removal, in the same commit.

## Shared Test Data

- Keep shared generators and fixtures in dedicated `*TestData.cs` files at the `Tests/` root.
- Keep hardcoded reference data for regression tests in `*Patterns.cs` files.
- Put stateless object-building helpers in `static` helper classes.

## Test Runner Changes

- Before changing test runner or test platform, verify console-output visibility and `ITestOutputHelper` behaviour against the repository's exact SDK, xUnit and test-platform versions. Quiet command output is easily misread as no test execution.
- Record the commands, verbosity settings, discovered-test counts, passed/failed/skipped totals and observed output behaviour from that investigation.
- Do not remove `ITestOutputHelper` or swap runners on the strength of an unverified limitation.

## Test Project README

Every `*.Tests` project README must include:

- A tests table with method count and expanded test-case count, since a `[Theory]` expands to multiple cases.
- Every trait category used in the project.
- A skipped-tests section listing each skip reason and count.
- A diagram of the `Tests/` folder layout.
