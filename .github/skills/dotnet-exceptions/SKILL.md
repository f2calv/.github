---
name: dotnet-exceptions
description: 'Audit and refactor C#/.NET exception throwing: replace raw or misused exception types, introduce area-specific subclasses of the shared domain exception base for recurring failures, and keep messages free of secrets. Use when reviewing throw sites, consolidating domain-exception usage, or adding a new failure area.'
argument-hint: 'mode={audit|apply} [scope=repository|project|area]'
---

# .NET Exceptions

The shared C# instructions own the always-on rules: which type to throw, catch only to handle,
translate or enrich, and one exception per file under `Exceptions/`. This skill is the procedure for
auditing an existing codebase against them and introducing area exception types.

The *domain exception base* is the solution's shared base type for domain and runtime failures, for
example `GenericException` in `CasCap.Common.Exceptions`. Its sibling `ConfigurationException`, in
the same package and namespace, covers imperative configuration checks. Substitute the solution's
own types below.

## Modes

| Mode | Outcome |
| --- | --- |
| `audit` | No edits. Report throw-site counts by type and area, misused types and candidate area exceptions. |
| `apply` | Implement the approved candidates, update callers and tests, and validate. |

## Audit

1. Inventory every `throw new <Type>(` in non-test source, excluding `bin`, `obj` and EF
   `Migrations`, and group the sites by repository, project folder, file and type:

   ```powershell
   Get-ChildItem src -Recurse -Filter *.cs |
       Where-Object FullName -notmatch '\\(bin|obj|Migrations)\\|Tests?\\' |
       Select-String -Pattern 'throw new (\w+)\(' -AllMatches |
       ForEach-Object { foreach ($m in $_.Matches) { [pscustomobject]@{ Type = $m.Groups[1].Value; File = $_.Path; Line = $_.LineNumber } } } |
       Group-Object Type | Sort-Object Count -Descending
   ```

2. Flag forbidden types: `Exception`, `SystemException`, `ApplicationException`,
   `NullReferenceException`, `IndexOutOfRangeException`.
3. Flag misclassified domain-exception-base sites. These are the common ones:
   - "not set", "not initialised", "please call X first" or "was not given" guards are object state,
     so use `InvalidOperationException`; so are mutually exclusive constructor inputs supplied
     together or not at all, and a missing embedded resource;
   - a bad method argument, including an unusable path or a conflicting dictionary key, uses the
     `ArgumentException` family with `paramName`;
   - a failed parse of a string uses `FormatException`;
   - a `switch` default for an unhandled subtype uses `NotSupportedException`, or `UnreachableException`
     when every subtype is handled;
   - bad data read from a file or export uses `InvalidDataException`, or an area exception when
     callers must tell it apart;
   - a site that already has an area type in the same package, such as an API client's
     `<Provider>Exception` or a `<Area>ConfigurationException`, uses that type;
   - options checked imperatively belong in options validation (`IValidateOptions<T>`,
     `IValidatableObject` and `ValidateOnStart()`), which surfaces `OptionsValidationException`;
   - a startup or composition check that options validation cannot express (no enabled feature, no
     registered sink, a null bound section, a registration helper returning null because a
     connection is unconfigured, mutually exclusive settings) uses the shared
     `ConfigurationException`;
   - a translating `catch` that drops the cause or copies `e.Message` keeps the type but passes the
     original as `InnerException` with a fixed message.
4. Cluster the remaining domain-exception-base sites by failure area: the subsystem plus the condition
   a caller, retry policy, health check or log query would want to distinguish. Read each message;
   the file name alone is not evidence.
5. A cluster is a candidate for an area exception when it has about three or more sites, or fewer
   with a concrete consumer that must distinguish it. Record the name, base type, owning project,
   site count and the consumer or query that benefits.
6. Report forbidden types, misclassified sites and candidates. Ask before `apply`, because new
   public exception types in a published package are an API addition and a release-train change.
7. When a consumer must adopt a new shared type before the package is published, confirm the
   approach: consumers that substitute the shared library by project reference in Debug compile
   against it immediately, while their Release and CI builds fail until the release train
   publishes it.

## Apply

Use the [classification and translation example](./examples/classification-and-translation.md)
to distinguish BCL/protocol failures from a justified area exception and its narrow caller catch.
The template uses an existing shared base; do not add a dependency merely to reproduce it.

1. Reuse an existing area type before creating one. Check the repository's `Exceptions/` folders
   first; for example, an area base such as `PaymentException` may already have a fitting
   `PaymentConfigurationException`.
2. Place each new type in the lowest project that owns the failure area, under `Exceptions/`, with a
   namespace ending in `.Exceptions`.
3. Shape:
   - Derive from the domain exception base, or from an area base when the area has several distinct
     failures. Make the area base non-sealed and every leaf `sealed`.
   - Provide the parameterless, message, and message-plus-inner constructors, or a primary
     constructor that carries structured properties (identifiers, ordinals, counts) a caller can
     inspect without parsing the message.
   - Document the type with one `<summary>` line saying when it is thrown.
4. Replace the throw sites. Keep each message, keep any `InnerException`, and remove credentials,
   tokens, connection strings, full local paths and personal data from messages while editing,
   including a request URL whose query string already carries an API key.
5. Before re-typing a site, find every consumer that classifies exceptions by type, such as a fault
   classifier, retry policy or health check, and confirm the new type lands in the same bucket.
   `InvalidDataException` derives from `IOException`, so a classifier that retries I/O failures
   would retry it; keep the old type where re-typing would change retry or recovery behaviour.
6. Update `catch` blocks, catch filters that match message text, and tests that matched the old
   type or message; `Assert.Throws` checks the exact type, so moving a site to a subtype still
   breaks its tests. Never widen a catch to `Exception` to absorb the change.
7. For a published package, record the new public types in the pull-request description and leave
   consumers on their pinned version until the release train reaches them.
8. Build in Release so that analyzers and multi-targeted frameworks compile; for a consumer adopting
   an unpublished shared type, build the Debug solution instead. Ask before running tests.

## Boundaries

- Do not add a shared-library reference to a contracts or client package only to reach the domain
  exception base; derive from `Exception` there.
- Do not convert BCL argument, state or protocol exceptions into area types, and never convert a
  requested `OperationCanceledException`.
- Keep this refactor separate from behaviour changes so that review can confirm only the thrown type
  changed.
- A validator shared between method arguments and persisted data keeps its area type rather than
  `ArgumentException`, because the same failure also reports bad stored data.

## Reference Area Types

| Type | Shape | Why it earned a type |
| --- | --- | --- |
| `ConfigurationException` | Sealed, beside the shared base | Startup and composition checks that options validation cannot express, in every consumer |
| `<Area>Exception` with stage leaves | Non-sealed area base; one sealed leaf per stage a caller or log query separates | Many integrity failures in one subsystem, roughly 100 sites |
| `<Protocol>Exception` | Non-sealed area base; existing mismatch types re-parented under it | Recurring protocol-ordering failures across a client and server |
| `<Provider>Exception` | Sealed, in the provider client project | Recurring provider failures a caller or log query separates |
| `CachingException` | Rejected | One site, a missing embedded script, which is `InvalidOperationException` |

## Maintaining This Skill

- Add each newly found misclassification pattern to the audit's list of misclassified sites.
- Refresh the audit command when repository layouts or test-project naming change.
- Record area types that proved useful, or unnecessary, in the reference table above.
- Compile the example against the real domain base when its contract changes; retain explicit
  checks for inner exceptions, unrelated I/O failures and cancellation propagation.
