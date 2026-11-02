---
description: 'C# test structure, credentials, diagnostics, naming, assertions, duplication and README conventions for xUnit v3 on Microsoft.Testing.Platform.'
applyTo: '**/*Tests/**/*.cs,**/*Tests/**/README.md,**/*Tests*.csproj'
---

# C# Testing

## Test Platform

- Tests run on `Microsoft.Testing.Platform` with xUnit v3 only — no VSTest packages, properties or
  command lines. Use the `dotnet-test-platform` skill for project setup, migration, `dotnet test`
  syntax, filters, coverage and CI steps.
- **Do not run tests without explicit user approval.**
- Start `dotnet test` from the target repository so its `global.json` selects the runner. An
  absolute `--project` path alone does not select that file; set the working directory explicitly
  in the same command invocation when the terminal starts elsewhere.

## Folder Structure

Organise every `*.Tests` project into subfolders by test type:

```text
Tests/
├── Unit/           # Self-contained tests: no DI container, no external services
└── Integration/    # Tests requiring DI, configuration or an external service
    └── TestBase.cs # Shared integration-test setup
```

Further subfolders are allowed for a genuinely distinct category; `Unit/` and `Integration/` stay primary.

## Unit Tests

- Place self-contained tests under `Tests/Unit/`.
- Do not inherit unit tests from an integration `TestBase`, and never let them require credentials or network access.
- Use domain-specific trait categories such as `Parsing`, `Serialization` or `Generation` — not `Unit`.
- May take `ITestOutputHelper` directly for diagnostic output.
- Prefer captured payloads stored as offline test assets over live calls.

## Integration Tests

- Tag every test that reaches configuration, credentials or an external service with
  `[Trait("Category", "Integration")]`, place it under `Tests/Integration/` and inherit `TestBase`.
- Skip, never fail, when no credential is configured. Read CI credentials only from secret-backed
  environment variables, and never commit or log a credential, account identifier or resolved
  secret, including in `appsettings*.json`.
- Keep tests read-only against shared remote services, and keep registration and interactive
  authentication out of the test run.
- The `dotnet-test-platform` skill's
  [integration test setup](../skills/dotnet-test-platform/references/integration-test-setup.md)
  covers `TestBase` wiring, the configuration chain, test environment naming and disposal.

## Fixtures and Disposal

- Dispose every `ServiceProvider` a test builds; make stateless helpers `static`; avoid shared
  mutable static state so each test is independently repeatable.
- Assert the actual startup failure, not a disposal wrapper: when `WebApplicationFactory` masks a
  fast startup exception, exercise it with `Host.StartAsync` and cover HTTP behaviour separately.
- In bUnit, prove component cleanup with `DisposeComponentsAsync`, not by disposing the wrapper.

## Diagnostic Output

- Write diagnostics through `ITestOutputHelper` or an `ILogger` routed to it. Never use
  `Debug.WriteLine` or `Console.WriteLine`, which the runner does not capture, and never call
  `Debugger.Break()`, which hangs CI.
- Emit only the values that explain a failure, and put the decisive ones in the assertion message.
  Prefer string interpolation over concatenation or composite format strings.

## Structure and Duplication

Tests face the same duplication gate as production code.

- Consolidate tests that differ only by input into a `[Theory]` with `[InlineData]`; keep `[Fact]`
  where setup or assertions do not parameterise cleanly.
- Extract a private helper named for what it asserts (`AssertGeneratedOutputIsAccepted`) when tests
  differ only by fixture or assertion, and extract a repeated arrange block by its third use, or its
  second when it is more than a few lines.
- Derive fixture variants from a shared private builder in the same `*TestData.cs`.
- Name tests after the method or feature under test (`UploadDocument`, `DetectsThresholdBreach`),
  with underscore-separated phases for lifecycles (`ItemLifecycle_CreateGetUpdateDelete`); never
  BDD sentences such as `Should_Return_Column_When_Given_Valid_Input`.

## Assertions

- Every test asserts meaningfully with the most specific assertion (`Assert.Equal`,
  `Assert.Single`, `Assert.Throws`), never a placeholder such as `Assert.True(true)`.
- Never swallow an exception from the system under test in a `try`/`catch`.
- Delete timing-only tests that assert nothing; move wanted measurements to BenchmarkDotNet.
- A fix for a reported issue adds a test that fails before it, names the issue in a comment and uses
  an offline captured input rather than a live service.

## Dead Code and Shared Data

- Delete commented-out, unreachable and permanently skipped tests, and the helpers, fields and
  `using` directives they leave unused, in the same commit.
- Keep shared generators and fixtures in `*TestData.cs` at the `Tests/` root, regression reference
  data in `*Patterns.cs`, and object builders in `static` helper classes. When splitting suites, move
  shared fakes into a support library or linked source; never reference another test executable.

## Test Project README

Every `*.Tests` project README must include:

- A tests table with method count and expanded test-case count, since a `[Theory]` expands to multiple cases.
- Every trait category used in the project.
- A skipped-tests section listing each skip reason and count.
- A diagram of the `Tests/` folder layout.
