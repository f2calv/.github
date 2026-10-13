---
description: 'C# / .NET coding conventions for style, application wiring, errors, cancellation, time, logging, XML documentation, HTTP and everyday performance defaults.'
applyTo: '**/*.cs'
---

# C# / .NET

Scoped companions carry the rest: configuration types in `dotnet.configuration`, controllers and
DTOs in `dotnet.webapi`, tests in `dotnet.testing`. Use the `dotnet-performance` skill for measured
hot-path work.

## Files and Types

- **One top-level type per file**, named after the type (`MyService.cs`, `WidgetConstants.cs`).
  Only nested types share a file. If you are about to add a second top-level type, create a new
  file. Two underscore-prefixed exceptions exist:
  - `_Enums.cs` holds every `enum` in the project, and only enums.
  - `_*Config.cs` (for example `_AppConfig.cs` for `record AppConfig`) groups a configuration root
    with its related config types.
- **Generic type filenames** encode type parameters in braces: `Widget{T}.cs`, `Cache{TKey,TValue}.cs`.
- **Interfaces** start with `I` and live in an `Abstractions` folder and namespace.
- **Custom exceptions** use the `Exception` suffix, one per file under `Exceptions/` with a namespace
  ending in `.Exceptions`. Nested private test doubles stay with their owning test type.
- **Wire constants** — request URIs, route templates, header names — go in a `static class` under a
  `Constants` folder and namespace, grouped per API surface (`RequestUris`, `UploadHeaders`), not
  beside DTOs in `Models`. This applies to APIs the code calls and APIs it exposes.
- **Namespaces** follow folders, except sub-folders under `Services`. Before creating a `Services`
  sub-folder, ask the user (yes/no) whether it introduces a sub-namespace.
- **`GlobalUsings.cs`** exists in every project root. Move a namespace imported by more than two files
  into it, delete the per-file duplicates, and re-check after refactors that add files.

## Style

The repository `.editorconfig` is authoritative. Its promoted tranche is build-enforced; remaining
preferences are suggestions, so apply both while writing:

- 4 spaces, LF, final newline; file-scoped namespaces with usings above; pure alphabetical usings
  with no `System.*` first and no blank-line groups, including in `GlobalUsings.cs`.
- Allman braces. Omit braces for single-statement `if`/`else`/`foreach`/`for`/`while`/`using` bodies.
- PascalCase types and members; no `this.`; `var` unless the type is not obvious; pattern matching (`is`, `not`, switch
  expressions); nullable reference types and implicit usings enabled; latest stable C# (currently 14.0).
- Expression bodies for accessors, properties, indexers, lambdas, constructors and single-expression
  methods, not operators or local functions. Move `=>` to the next line when it would scroll.
- Declare interface members with explicit `public` accessibility; the build enforces accessibility
  modifiers on interface members as well as implementations.
- Explicit interface properties use accessor blocks (`{ get => …; }`), never `=>`, and carry
  `/// <inheritdoc/>`.
- Wrap long parameter lists one per line, with the closing parenthesis and any `: base(...)` on its
  own line.
- Separate public properties with a blank line; keep private backing fields on consecutive lines.
- Place `ToString`, `GetHashCode` and `Equals` overrides at the bottom, above private helper regions.
- Prefer `record` types with `get; init;` properties where value equality is useful.

## Constructors and Dependency Injection

- **Primary constructors**: use parameters directly; never copy them to fields
  (`private ILogger _logger = logger;`). Abstract base classes may expose a `protected` field for
  inheritors.
- **Parameter order**: `ILogger`, then `IOptions<T>` / `IOptionsMonitor<T>`, then `TimeProvider`, then
  application services.
- **Service names** use a `Svc` suffix (`orderSvc`, not `orderService`).
- **Options access**: read `.Value` / `.CurrentValue` inline at the point of use; never cache it in a
  field or local.
- **Seal concrete classes** unless designed for inheritance (`virtual`/`abstract` members or a
  documented base). Services, background services, entities, converters and middleware default to
  `sealed`; unsealing later is non-breaking.

## Constants and Enums

- **No magic strings**: a literal used as a key or identifier in more than one place becomes a
  `const` built with `nameof()` (`public const string SummaryValues = nameof(SummaryValues);`).
- **Enums** suit closed sets within one assembly or tightly coupled projects. For values crossing
  library, configuration, environment or wire boundaries, use a `static class` of `const string`
  fields via `nameof()`. When startup validation is needed, expose `IReadOnlySet<string> ValidNames`
  built by reflection over the class's own constants.

## Application Wiring

- **`Program.cs` is wiring-only** in hosted applications: configuration, DI, logging, middleware or
  hosted services, then start. Extract logic into dedicated types. Linear console samples may keep an
  end-to-end flow when extraction would obscure it.
- **Centralise environment access** through `Microsoft.Extensions.Configuration`; do not scatter
  `Environment.GetEnvironmentVariable`. Centralised reads of standard platform, CI and
  build-provenance variables are permitted.
- **Validate options at startup** with data annotations, `IValidateOptions<T>` or validators plus
  `ValidateOnStart()`. Validate external input at the boundary with actionable messages that
  contain no secrets or personal data.
- **Guard target-framework-specific APIs** in multi-targeted libraries with preprocessor symbols such
  as `#if NET8_0_OR_GREATER`.

## Async, Errors and Cancellation

- Always await async calls; never block with `.Result`, `.Wait()` or `GetAwaiter().GetResult()`.
- Thin wrappers that only return another async call (no `using`, `try`/`catch` or further `await`)
  drop `async`/`await` and return the `Task`/`ValueTask` directly.
- Never mark a callback `async` just to await a no-op; the conversion can become unobservable
  `async void`.
- Use `ValueTask` for frequently synchronous completions and `Task` when the call almost always goes
  async. Never cache, await twice or concurrently await a `ValueTask`; call `.AsTask()` instead.
- Library projects use `ConfigureAwait(false)` on every `await` that does not need `HttpContext`
  afterwards; application entry points may omit it.
- **Catch only to handle, translate or enrich.** Never log-and-rethrow unchanged or swallow into a
  default. Wrap with operation context, keep the original as `InnerException`, use domain exception
  types when callers must distinguish conditions, and keep context free of credentials, tokens,
  connection strings, full local paths and personal data.
- Use result types, `Try*` methods or nullable returns for expected absence and validation outcomes.
- **Cancellation**: pass the available `CancellationToken` to every cancellable call — database, HTTP,
  file, stream, queue, delay, lock, paging and nested services. Pass `CancellationToken.None`
  explicitly, and locally, when an operation must outlive the caller. Never convert a requested
  `OperationCanceledException` into an error.

## Background Work and Shutdown

- Propagate `ExecuteAsync`'s `stoppingToken` everywhere and use cancellable waits
  (`Task.Delay(delay, timeProvider, stoppingToken)`); never poll a flag around an uncancellable sleep.
- No fire-and-forget: retain and await tasks whose failure or completion belongs to the lifecycle.
- Dispose owned timers, streams, registrations and scopes deterministically before the host exits.
- The owner of a linked `CancellationTokenSource` cancels it with `CancelAsync`, awaits its workers,
  disposes it in `finally` or at shutdown, and clears retained references.
- Prefer bounded queues with explicit backpressure over unbounded in-memory work collections.

## Time

- Never call `DateTime.UtcNow`/`Now`/`Today` or `DateTimeOffset.UtcNow`/`Now` in production code.
  Inject a singleton `TimeProvider` (`TimeProvider.System`) and use `GetUtcNow()`, the
  `Task.Delay(TimeSpan, timeProvider, ct)` overload and `timeProvider.CreateTimer(...)`, so tests
  (`FakeTimeProvider`) and simulations can control the clock.
- Static helpers may accept `TimeProvider? timeProvider = null`, falling back to `TimeProvider.System`.
- Direct use is permitted only in tests, `TimeProvider` implementations, and static, `const` or
  default-property initialisers where DI is unavailable.

## Logging

- Use `ILogger<T>` with constant message templates for application diagnostics — never
  `Console.WriteLine` or `Debug.WriteLine` — and no string interpolation or concatenation.
- `{ClassName}` is the first parameter, supplied as `nameof(EnclosingClass)`.
- Parameters are PascalCase, unquoted, unique within a template, and named after the property —
  never with a `.Value`-derived or `Val` suffix (`{ServiceFamily}` for `config.Value.ServiceFamily`).
- Pass enum values and symbols as `nameof()` arguments, but do not add `nameof()` fields merely as
  labels: write `"{ClassName} ServiceFamily={ServiceFamily}"`, not
  `"{ClassName} {ServiceFamily}={ServiceFamilyValue}"`.
- **Hot paths** (loops, channel readers, stream consumers, message processors) use source-generated
  `[LoggerMessage]`: `private static partial void` methods at the bottom of the partial class or in
  `{ClassName}.Logging.cs`, first parameter `ILogger logger`, called as `LogXxx(logger, ...)`. Leave
  dynamic-level `logger.Log(level, ...)` calls unconverted.
- Never log secrets, tokens, authorisation headers, connection strings, signed-URL queries, full
  local paths or personal data.

## XML Documentation

- Document every public and internal type, member and enum member. Test projects document types and
  properties but not test methods.
- Document on the interface; implementations use `/// <inheritdoc/>`. For enum-typed parameters and
  properties use `<inheritdoc cref="EnumType" path="/summary"/>`, keeping value-adding `<remarks>`.
- Reference .NET types and namespaces with `<see cref="Fully.Qualified.Name" />`, not plain text.
- `<summary>` is one or two sentences defining the member. Move detail, examples and "Defaults to …"
  text into `<remarks>`. Collapse a line of roughly 120 characters or fewer into
  `/// <summary>Text.</summary>`.
- Never delete an inline comment hyperlink; move it into `<remarks>` as `<see href="…" />`.

## Warnings

- Suppress diagnostics only centrally in `Directory.Build.props` with a stated reason, never with
  `#pragma warning disable` or `[SuppressMessage]`. Fix a new warning rather than suppressing it.

## HTTP, Streams and Files

- Obtain `HttpClient` from `IHttpClientFactory` or a typed client; never construct one per request.
- Stream large payloads unless the method explicitly returns a byte array. Check status and content
  before deserialising, and put the status and redacted body in domain exceptions.
- Dispose `HttpRequestMessage`, `HttpResponseMessage`, streams and registrations with `using` /
  `await using`.
- Build temporary paths with `Path.Combine(Path.GetTempPath(), Path.GetRandomFileName())` and delete
  them in `finally`; never use `Path.GetTempFileName()`.

## Performance Defaults

- Measure with BenchmarkDotNet, `dotnet-counters`, `dotnet-trace` or a load test before adding
  complexity; clarity wins in demonstration code.
- Use `FrozenDictionary`/`FrozenSet`, stored as the concrete type, for collections built once at
  startup, and `System.Threading.Lock` rather than `object` for dedicated locks.

## Correctness and Security

- Compare calculated `float`/`double` values against a domain tolerance, not exact equality, unless
  exact identity is part of the contract. Remove invariant expressions such as `value - value`.
- Use `RandomNumberGenerator` for tokens, secrets, identifiers and security-sensitive paths, and
  `Random.Shared` only for clearly non-security behaviour. Never create a `Random` per call.
- When an immutable protocol mandates legacy cryptography, keep the exact algorithm, document the
  constraint beside it and accept the specific analysis finding with that rationale. Never swap in an
  incompatible algorithm, use `NOSONAR` or add a repository-wide suppression.
