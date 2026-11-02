# Integration Test Setup

How integration tests share configuration, logging, services and credentials through `TestBase`
under the always-on [testing instructions](../../../instructions/dotnet.testing.instructions.md).

## Rules

- Apply `[Trait("Category", "Integration")]` to every test that reaches configuration, credentials or an external service.
- Place them under `Tests/Integration/` and share configuration, logging and service setup through `TestBase`.
- Inherit from `TestBase(output)`, which wires up `ILoggerFactory` (routed to xUnit output), `IConfiguration` and, where needed, a DI container.
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
- Skip rather than fail when no credential is configured, so a contributor without access still gets a green credential-free run.
- Read CI credentials only from secret-backed environment variables. Never commit a credential, token, account identifier or tenant-specific name, and never write a resolved secret to test output.
- Never commit a secret to an `appsettings*.json` file to make a test pass.
- Keep integration tests read-only against the target service wherever the service supports it. Do not create, update or delete shared remote resources as a side effect of a test run.
- Perform account registration, linking or interactive authentication outside the test run. Never initiate an interactive login or a registration flow in CI.
- Exception: a lightweight integration test needing only `HttpClient` may take `ITestOutputHelper` directly without `TestBase`.
