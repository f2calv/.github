# .NET 11 Upgrade Highlights

Research entry points for .NET 10 to 11, checked **2026-10-24** against Microsoft's RC2
documentation. **Not a GA checklist:** .NET 11 is currently a release candidate, with GA expected
in November 2026. Recheck release and feature status before proposing changes; prerelease
adoption requires explicit approval. This reference contains no fixed package versions.

## Official Starting Points

| Area | Official documentation |
| --- | --- |
| Release status and support | [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core), [release records](https://github.com/dotnet/core/tree/main/release-notes), [.NET 11 overview](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/overview) |
| Runtime and base libraries | [Runtime changes](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/runtime), [library changes](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/libraries) |
| Language and tools | [C# 15](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-15), [SDK/tooling](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/sdk) |
| Web and Blazor | [ASP.NET Core 11 features](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-11?view=aspnetcore-11.0), [10 to 11 migration](https://learn.microsoft.com/en-us/aspnet/core/migration/100-to-110?view=aspnetcore-11.0) |
| Data access | [EF Core 11 features](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-11.0/whatsnew), [EF Core breaking changes](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-11.0/breaking-changes) |
| Compatibility | [.NET 11 breaking changes](https://learn.microsoft.com/en-us/dotnet/core/compatibility/11), [ASP.NET Core breaking changes](https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/11/overview?view=aspnetcore-11.0), [API obsoletions](https://learn.microsoft.com/en-us/dotnet/core/compatibility/core-libraries/11/obsolete-apis) |

These are starting points: follow the specific feature/diagnostic links for prerequisites and
semantics. Read the complete applicable breaking-change indexes, not only the watchlist below.

## High-Value Opportunities to Investigate

| Highlight | Look for in the codebase | Potential win and guardrail | Official detail |
| --- | --- | --- | --- |
| Runtime-native async, JIT and NativeAOT dispatch improvements | Async-heavy services, allocation/startup profiles, interface-heavy AOT paths | Benchmark the platform upgrade first; separate automatic runtime gains from compiler/configuration-dependent gains. Check Runtime Async activation requirements; don't rewrite `Task`/`ValueTask` signatures by rote. | [Runtime](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/runtime) |
| C# 15 collection expression arguments | Collection construction that needs capacity or a custom comparer and therefore couldn't use collection expressions cleanly | Simplify initialization while retaining capacity and equality semantics; syntax alone is not a measured speedup. | [Collection expression arguments](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-15#collection-expression-arguments) |
| C# 15 unions and closed hierarchies | Internal discriminated results, tagged payloads, exhaustive switches and boilerplate case hierarchies | Consider clearer domain modeling and exhaustiveness checks. Verify serializer/generator support and public API consequences before replacing established abstractions. | [Unions](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-15#union-types), [closed hierarchies](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-15#closed-hierarchies) |
| Memory-backed stream types | `MemoryStream` wrappers, `ToArray()` copies, custom streams around memory/sequences/strings | Investigate `ReadOnlyMemoryStream`, `WritableMemoryStream`, `ReadOnlySequenceStream` and `StringStream` for fewer copies/custom wrappers. Verify buffer lifetime, writability and seeking contracts. | [Libraries](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/libraries) |
| System.Text.Json JSONL, union and source-generation improvements | Hand-rolled JSON Lines writers, custom converters and reflection-heavy serialization | Remove proven redundant plumbing or allocations; preserve wire format, polymorphism, null/ignore rules and generated metadata. | [Libraries](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/libraries) |
| Async validation and cache diagnostics | Custom async validation pipelines, startup validators, bespoke `MemoryCache` instrumentation | Investigate `AsyncValidationAttribute`, `IAsyncValidatableObject`, `IAsyncStartupValidator` and built-in cache metrics. Verify integration, cancellation and metric naming/cardinality before adoption. | [Libraries](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/libraries) |
| Process run-and-capture helpers | Process wrappers manually coordinating stdout, stderr and exit completion | Consider built-in helpers instead of maintaining lifecycle code. Preserve cancellation, exit-code handling, output bounds and logging/privacy behavior. | [Process API expansion](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/libraries#process-api-expansion) |
| Blazor `BasePath`/`DisplayName` and CSP-friendly navigation template | Hand-maintained base paths, duplicated display labels, inline navigation event handlers | Reduce duplicated metadata or inline JavaScript where applicable. Validate hosting subpaths, localization and browser behavior; don't regenerate an existing frontend from a template. | [Blazor changes](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-11?view=aspnetcore-11.0#blazor), [migration](https://learn.microsoft.com/en-us/aspnet/core/migration/100-to-110?view=aspnetcore-11.0) |
| EF complex-type improvements | Workarounds for complex types with TPT/TPC, verbose nested property configuration, missing nested keys/indexes | Reassess modeling workarounds only with the actual provider's support verified. EF11 requires .NET 11; inspect SQL, schema/migrations and query behavior, not just model compilation. | [EF Core 11](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-11.0/whatsnew#complex-types) |
| SDK and test CLI improvements | Custom test orchestration/timeouts, template setup, expensive logging diagnostic workarounds | Evaluate native runner capabilities and CA1873 refinements before adding scripts or suppressions. Preserve the repository's MTP configuration and check exact SDK/runner syntax. | [SDK/tooling](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/sdk) |

Investigate additional features only when the code warrants them: networking/compression, numeric
APIs, SIMD, desktop/mobile or file-based apps. New APIs aren't automatically faster or preferable.
C# 15 memory safety remains a **preview feature** in the checked documentation; release availability
does not authorize preview flags or experimental APIs.

## Deprecation and Behavior Watchlist

| Change | Search cue and required assessment | Official source |
| --- | --- | --- |
| Raised CPU baseline and ReadyToRun targets | Check actual x86/x64/Arm64 deployment hardware, VM-exposed instruction sets and AOT/R2R targets. A container does not abstract away CPU requirements. Distinguish unsupported hardware from supported hardware with different startup costs. | [Updated minimum hardware requirements](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/runtime#updated-minimum-hardware-requirements) |
| `IStartupValidator` obsolete (`SYSLIB0066`) | Find custom implementations and DI registrations; migrate to `IAsyncStartupValidator` using the documented guidance. Do not register the same implementation under both interfaces. | [Obsoletions](https://learn.microsoft.com/en-us/dotnet/core/compatibility/core-libraries/11/obsolete-apis) |
| Boolean-padding RSA overloads obsolete (`SYSLIB0064`) | Find `RSACryptoServiceProvider.Encrypt`/`Decrypt` calls with Boolean padding; use `RSAEncryptionPadding` overloads while preserving the chosen padding and compatibility. | [Obsoletions](https://learn.microsoft.com/en-us/dotnet/core/compatibility/core-libraries/11/obsolete-apis) |
| ASP.NET obsolete APIs removed | Check `ConcurrencyLimiter`, MVC compatibility options and removed Blazor/tag-helper APIs. Follow each removal's replacement guidance, not a new suppression. | [ASP.NET breaks](https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/11/overview?view=aspnetcore-11.0) |
| OpenAPI dependency and document behavior changes | Inspect `Microsoft.OpenApi` 3.x consumers, transformers and clients; verify document version defaults and generated contracts before accepting output changes. | [ASP.NET breaks](https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/11/overview?view=aspnetcore-11.0) |
| Hosting, protocol, authentication and telemetry behavior | Check host shutdown/error handling, DI disposal, middleware/proxy interoperability, passkeys, Blazor antiforgery, HTTP trace tags and dependent dashboards. These may compile unchanged. | [.NET breaks](https://learn.microsoft.com/en-us/dotnet/core/compatibility/11), [ASP.NET breaks](https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/11/overview?view=aspnetcore-11.0) |
| EF removals, obsolete mappings and provider changes | Inspect owned JSON collections without explicit keys (obsolete), removed `EFOptimizeContext`, missing explicit Design-package references, and provider/SqlClient compatibility. Cosmos users must assess removed sync I/O and loss of unmapped properties on save. | [EF breaks and mitigations](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-11.0/breaking-changes) |
| Numerical, parsing and archive behavior changes | Match rounding/conversion, date/time parsing, ZIP/TAR validation and compression changes to real usages. Add focused behavior checks rather than assuming identical results. | [.NET breaks](https://learn.microsoft.com/en-us/dotnet/core/compatibility/11) |

Treat this watchlist as incomplete and time-sensitive. Distinguish compiler warnings, source/binary
removals, runtime behavior changes and support constraints in the user report. Reverify the
documented replacement for each matched usage; a feature announcement is not a migration recipe.
