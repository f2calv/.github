# Integration Test Setup

How integration tests share configuration, logging, services and credentials through `TestBase`
under the always-on [testing instructions](../../../instructions/dotnet.testing.instructions.md).

## Rules

- Follow the linked testing instructions for classification and live opt-in.
- When setup is shared, `TestBase(output)` can wire `ILoggerFactory` (routed to xUnit output),
  `IConfiguration` and, where needed, a DI container.
- Build configuration in a documented order: the test `appsettings` chain, then user secrets for local runs, then environment variables for CI, then any secret store the repository uses.
- Keep test connection strings in configuration, not C# fallback literals. When using the shared
  configuration extensions, select the `Test` environment to load optional `appsettings.Test.json`,
  copy the settings to the test output, and preserve CI environment-variable precedence. An absent
  test file is allowed; required values must still be supplied by another provider. Tracked files
  may contain only synthetic disposable-local-service defaults, never real credentials.
- Check for an existing deployment environment before choosing the test overlay name. Preserve
  explicitly agreed repository-specific environment/file names; never repurpose deployed
  configuration to satisfy the default test naming convention.
- Expose commonly-used services as `protected` fields on `TestBase` rather than resolving them again in each test class.
- Expose `protected ITestOutputHelper _output` on `TestBase`. Subclasses use that field directly; capturing the constructor parameter in a primary constructor while also passing it to the base is compile error **CS9107**.
- Dispose any `ServiceProvider` the fixture creates through `IDisposable` or `IAsyncDisposable`.
- Dispose fixture-owned configuration providers/watchers through a disposable concrete owner such
  as `ConfigurationManager`; do not assume `IConfigurationRoot` implements `IDisposable`.
- Give each in-process host a unique EF InMemory database name, so mutable fixture rows cannot leak
  across hosts even when tests run sequentially. Prove isolation with a two-host regression.
- Preserve the built-in options pipeline when startup performs async options validation. Supply
  synthetic fixture configuration or `PostConfigure<T>` instead of replacing `IOptions<T>` with
  `OptionsWrapper<T>`.
- Keep configuration-skip environment overrides local to the fixture that owns them and restore
  previous values; missing-configuration guard tests may require those settings to remain absent.
- Skip rather than fail when no credential is configured, so a contributor without access still gets a green credential-free run.
- A negative opt-in regression must pass, not become a skipped test. xUnit's dynamic
  `SkipException` can propagate through `Assert.Throws`; capture only that expected exception and
  assert both the refusal and untouched setup. For collection fixtures, record unavailable state
  without initializing clients, then perform the dynamic skip inside actual test setup.
- Read CI credentials only from secret-backed environment variables. Never commit a credential, token, account identifier or tenant-specific name, and never write a resolved secret to test output.
- Never commit a secret to an `appsettings*.json` file to make a test pass.
- Keep integration tests read-only against the target service wherever the service supports it. Do not create, update or delete shared remote resources as a side effect of a test run.
- Perform account registration, linking or interactive authentication outside the test run. Never initiate an interactive login or a registration flow in CI.
- Exception: a lightweight integration test needing only `HttpClient` may take `ITestOutputHelper` directly without `TestBase`.
