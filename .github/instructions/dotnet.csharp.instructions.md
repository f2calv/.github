---
description: 'C# / .NET coding conventions for files and types, style, constructors, wiring, errors, cancellation, time, logging, XML documentation, HTTP and performance defaults.'
applyTo: '**/*.cs'
---

# C# / .NET

Scoped companions carry the rest: configuration types in `dotnet.configuration`, controllers and
DTOs in `dotnet.webapi`, tests in `dotnet.testing`. Skills own deeper procedures: `dotnet-apphost`
for bootstrapping, `dotnet-exceptions` for exception types, `dotnet-background-pipelines` for queued
work, `dotnet-performance` for measured hot paths and [dotnet-grpc](../skills/dotnet-grpc/SKILL.md)
for RPC.

## Files and Types

- **One top-level type per file**, named after the type; only nested types share a file. Two
  exceptions: `_Enums.cs` holds every enum in the project and nothing else, and `_*Config.cs` (such
  as `_AppConfig.cs`) groups a configuration root with its related config types.
- Generic type filenames encode type parameters in braces: `Widget{T}.cs`, `Cache{TKey,TValue}.cs`.
- **Interfaces** start with `I`, live in an `Abstractions` folder and namespace, and name a role or
  capability (`IMessageGateway`), never an implementing class with an `I` prefix or a `Service`
  suffix. Rename an existing interface only when already changing it; that is a breaking change.
- **Remove single-implementation interfaces** unless tests substitute them, another assembly
  consumes them as a contract or extension point, or a second implementation exists. Never add one
  for a speculative future implementation.
- **Services** (DI-registered application types) live in `Services` with a `Service` suffix, or a
  more specific role suffix (`Handler`, `Factory`, `Manager`, `Coordinator`). Group supporting types
  in a `Services` sub-folder or `ServiceName.SubCategory.cs` partials. Types outside DI keep their
  role suffix (`Validator`, `Converter`).
- **Extension classes** live in `Extensions`, named after the extended type
  (`ServiceCollectionExtensions`), including endpoint-mapping and host-registration extensions. Never
  use a framework namespace such as `Microsoft.AspNetCore.Builder`; keep them to wiring and delegate
  behaviour to the owning service.
- **Models** (DTOs, payloads, options and configuration records) live in `Models`; EF Core entities
  follow the EF Core instructions. **Custom exceptions** use the `Exception` suffix, one per file in
  `Exceptions/` with a `.Exceptions` namespace. Nested private test doubles stay with their test type.
- **Wire constants** (request URIs, route templates, header names) go in a `static class` per API
  surface under `Constants` (`RequestUris`, `UploadHeaders`), for APIs called and exposed alike.
- Namespaces follow folders, except that sub-folders of `Services` keep the `Services` namespace.
- Every project root has a `GlobalUsings.cs`; move a namespace imported by more than two files into
  it and delete the per-file duplicates, re-checking after refactors.

## Style

The repository `.editorconfig` is authoritative; apply its suggestions as well as its build-enforced
rules:

- 4 spaces, LF, final newline; file-scoped namespaces with usings above, purely alphabetical with no
  `System.*` first and no blank-line groups, including in `GlobalUsings.cs`.
- Allman braces; omit braces for single-statement `if`/`else`/`foreach`/`for`/`while`/`using`
  bodies.
- PascalCase types and members; no `this.`; `var` unless the type is not obvious; pattern matching;
  nullable reference types and implicit usings enabled; the latest stable C# (currently 14.0).
- Expression bodies for accessors, properties, indexers, lambdas, constructors and single-expression
  methods, not operators or local functions; move `=>` to the next line when it would scroll.
- Interface members declare explicit `public`. Explicit interface properties use accessor blocks
  (`{ get => …; }`), never `=>`, with `/// <inheritdoc/>`.
- Wrap long parameter lists one per line, with the closing parenthesis and any `: base(...)` on its
  own line. Separate public properties with a blank line; keep private backing fields consecutive.
- Put `ToString`, `GetHashCode` and `Equals` overrides at the bottom, above private helper regions.
- Prefer `record` types with `get; init;` properties where value equality is useful.

## Constructors and Dependency Injection

- **Primary constructors**: use parameters directly and never copy them to fields; abstract base
  classes may expose a `protected` field for inheritors.
- **Order**: `ILogger`, then `IOptions<T>`/`IOptionsMonitor<T>`, then `TimeProvider`, then
  application services; at most seven constructor or method parameters. Move a cohesive group into
  a dedicated type, such as an `<Area>Metrics` class owning its meter instruments, and pass a small
  state object instead of flags.
- **Names** follow the type without the `I` (`realtimeConnectionHub`); `Service` types use a `Svc`
  suffix (`orderSvc`). `ILogger<T>` is `logger`, `TimeProvider` is `timeProvider`, a single options
  dependency is `config`, and several are named after their types (`commsConfig`).
- Read options `.Value`/`.CurrentValue` inline at the point of use; never cache it.
- **Seal concrete classes** unless designed for inheritance. Services, background services,
  entities, converters and middleware default to `sealed`.

## Constants and Enums

- **No magic strings**: a literal used as a key or identifier in more than one place becomes a
  `const` built with `nameof()` (`public const string SummaryValues = nameof(SummaryValues);`).
- Enums suit closed sets within one assembly or tightly coupled projects. Values crossing library,
  configuration, environment or wire boundaries use a `static class` of `nameof()` constants, with
  an `IReadOnlySet<string> ValidNames` built by reflection when startup validation needs it.

## Application Wiring

- `Program.cs` is wiring only in hosted applications: configuration, DI, logging, middleware or
  hosted services, then start. Linear console samples may keep an end-to-end flow.
- Use modern hosting in applications, samples and test hosts: `WebApplication.CreateBuilder` or an
  `AppHost` composition root, never `Startup`/`UseStartup`. Expose a public partial `Program` marker
  for `WebApplicationFactory`.
- Keep composition roots shallow: one registration method per feature that returns early when the
  feature is off, with shared switches in one small state type, so no method exceeds a cognitive
  complexity of 15.
- No hard-coded absolute URIs or file paths; read them from configuration, or omit decorative
  metadata such as OpenAPI contact links.
- Read environment through `Microsoft.Extensions.Configuration`, not scattered
  `Environment.GetEnvironmentVariable` calls; centralised reads of standard platform, CI and
  build-provenance variables are permitted.
- Validate options at startup (data annotations, `IValidateOptions<T>` or validators with
  `ValidateOnStart()`), and external input at the boundary with actionable messages free of secrets
  and personal data.
- Guard target-framework-specific APIs in multi-targeted libraries with symbols such as
  `#if NET8_0_OR_GREATER`.

## Async, Errors and Cancellation

- Always await; never block with `.Result`, `.Wait()` or `GetAwaiter().GetResult()`. Thin wrappers
  with no `using`, `try` or further `await` return the task directly. Never mark a callback `async`
  just to await a no-op; it can become an unobservable `async void`.
- Use `ValueTask` for frequently synchronous completions and `Task` otherwise; never cache, await
  twice or concurrently await a `ValueTask` (use `.AsTask()`).
- Libraries use `ConfigureAwait(false)` on every `await` that does not need `HttpContext`
  afterwards; application entry points may omit it.
- **Catch only to handle, translate or enrich**: never log-and-rethrow unchanged or swallow into a
  default. Wrap with operation context, keep the original as `InnerException`, and keep context
  free of credentials, tokens, connection strings, full local paths and personal data. Use result
  types, `Try*` methods or nullable returns for expected absence and validation outcomes.
- **Throw by who must act.** Never throw `Exception`, `SystemException`, `ApplicationException`,
  `NullReferenceException` or `IndexOutOfRangeException`.
  - Caller mistakes and object state: the `ArgumentException` family via `ThrowIf*` helpers,
    `InvalidOperationException`, `NotSupportedException` and `ObjectDisposedException.ThrowIf`.
  - Protocol boundaries: `JsonException` in converters, `RpcException` in gRPC services and
    `McpException` in MCP tools.
  - Domain and runtime failures: a type derived from the solution's shared domain exception base,
    with a dedicated `<Area>Exception` for recurring failures in one area; throw the base itself only
    for a one-off failure nobody would catch separately. Contract packages that
    avoid the shared library derive from `Exception`.
- **Cancellation**: pass the available token to every cancellable call; pass
  `CancellationToken.None` explicitly where an operation must outlive the caller. Never turn a
  requested `OperationCanceledException` into an error. Await shutdown without a catch block via
  `Task.Delay(Timeout.Infinite, token).ConfigureAwait(ConfigureAwaitOptions.SuppressThrowing)`; a
  `catch` that logs passes the exception to the logger.

## Background Work and Shutdown

- Propagate `stoppingToken` everywhere and use cancellable waits
  (`Task.Delay(delay, timeProvider, stoppingToken)`), never a flag polled around a sleep.
- No fire-and-forget: retain and await tasks whose failure or completion belongs to the lifecycle.
- Dispose owned timers, streams, registrations and scopes deterministically before the host exits.
  The owner of a linked `CancellationTokenSource` cancels it with `CancelAsync`, awaits its workers,
  disposes it and clears retained references.
- Prefer bounded queues with explicit backpressure over unbounded in-memory collections.

## Time

- Never call `DateTime.UtcNow`/`Now`/`Today` or `DateTimeOffset.UtcNow`/`Now` in production code.
  Inject a singleton `TimeProvider` and use `GetUtcNow()`, the
  `Task.Delay(TimeSpan, timeProvider, ct)` overload and `CreateTimer(...)`, so tests can use
  `FakeTimeProvider`. Static helpers may take `TimeProvider? timeProvider = null`.
- Direct use is permitted only in tests, `TimeProvider` implementations and static, `const` or
  default-property initialisers where DI is unavailable.

## Logging

- Use `ILogger<T>` with constant message templates, never `Console.WriteLine`, `Debug.WriteLine`,
  interpolation or concatenation. The first parameter is `{ClassName}` from
  `nameof(EnclosingClass)`.
- Parameters are PascalCase, unquoted, unique and named after the property, never with a `Value` or
  `Val` suffix: `"{ClassName} ServiceFamily={ServiceFamily}"`. Pass enum values and symbols as
  `nameof()` arguments, but never add `nameof()` fields merely as labels.
- **Correlation scopes**: open `logger.BeginScope` once at a unit of work's entry with its
  correlation IDs, keyed from one constants class and named like the template parameters. Do not
  add a method parameter only to log an ID. Scopes flow through `await` and are exported when the
  provider sets `IncludeScopes = true`. Still include the ID explicitly in Warning, Error and
  Critical templates.
- Level by who must act: missing data or configuration that should exist is a Warning; a feature
  deliberately not configured is Debug, as is routine per-item progress.
- **Hot paths** (loops, channel readers, stream consumers, message processors) use
  source-generated `[LoggerMessage]` `private static partial void` methods, first parameter
  `ILogger logger`, at the bottom of the class or in `{ClassName}.Logging.cs`. Give their
  parameters the value's own type rather than calling `ToString()`. Leave dynamic-level
  `logger.Log(level, ...)` calls unconverted.
- Guard every other `logger.LogXxx(...)` with `if (logger.IsEnabled(LogLevel.Xxx))` (CA1873).
- Never log secrets, tokens, authorisation headers, connection strings, signed-URL queries, full
  local paths or personal data.

## XML Documentation

- Document every public and internal type, member and enum member; test projects document types
  and properties but not test methods.
- Document on the interface and use `/// <inheritdoc/>` on implementations; for enum-typed members
  use `<inheritdoc cref="EnumType" path="/summary"/>`, keeping value-adding `<remarks>`.
- Reference .NET types with `<see cref="Fully.Qualified.Name" />`, not plain text.
- `<summary>` is one or two defining sentences, collapsed onto one line when about 120 characters or
  fewer; detail, examples and defaults go in `<remarks>`. Move inline comment links into `<remarks>`
  as `<see href="…" />`; never delete them.

## Warnings

- Fix new warnings. Suppress only centrally in `Directory.Build.props` with a stated reason, never
  with `#pragma warning disable` or `[SuppressMessage]`.

## HTTP, Streams and Files

- Obtain `HttpClient` from `IHttpClientFactory` or a typed client, never one per request.
- Stream large payloads unless the method returns a byte array. Check status and content before
  deserialising, and put the status and redacted body in domain exceptions.
- Dispose request and response messages, streams and registrations with `using`/`await using`.
- Build temporary paths with `Path.Combine(Path.GetTempPath(), Path.GetRandomFileName())` and delete
  them in `finally`; never use `Path.GetTempFileName()`.

## Performance Defaults

- Measure with BenchmarkDotNet, `dotnet-counters`, `dotnet-trace` or a load test before adding
  complexity; clarity wins in demonstration code.
- Use `FrozenDictionary`/`FrozenSet`, stored as the concrete type, for collections built once, and
  `System.Threading.Lock` for dedicated locks.
- Pass metric tags as `new TagList([...])` to avoid the `params` array beyond three tags; mark
  SonarQube S3878 on that expression a false positive.

## Correctness and Security

- Compare calculated `float`/`double` values against a domain tolerance unless exact identity is
  the contract; remove invariant expressions such as `value - value`.
- Use `RandomNumberGenerator` for tokens, secrets, identifiers and security-sensitive paths, and
  `Random.Shared` only for non-security behaviour; never create a `Random` per call.
- When an immutable protocol mandates legacy cryptography, keep the exact algorithm, document the
  constraint beside it and accept that specific finding with the rationale; never swap algorithms,
  use `NOSONAR` or add a repository-wide suppression.
