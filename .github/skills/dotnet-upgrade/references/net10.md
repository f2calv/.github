# .NET 10 Retained Baseline

Official entry points rechecked **2026-11-05**. Keep this reference while .NET 10 applications,
library assets and container images remain supported. An installed .NET 11 SDK does not authorize
using .NET 11 APIs or C# 15-only syntax in .NET 10 source.

| Area | Official sources |
| --- | --- |
| Release and support | [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core), [release records](https://github.com/dotnet/core/tree/main/release-notes) |
| Runtime, libraries and tools | [.NET 10 overview](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/overview) |
| Language | [C# 14](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14) |

Use the overview's workload and compatibility links for the actual migration; for upgrades from
.NET 8, assess .NET 9 changes as well. Recheck current stable SDK/runtime patches and independent
provider/workload release schedules rather than treating every package as version 10.

## Code-Specific Opportunities

| Candidate | Search cues | Guardrail |
| --- | --- | --- |
| C# 14 field-backed properties | Private backing fields used only by one property's accessors | Preserve accessor validation, attributes, initialization and serialization behavior |
| C# 14 extension members | Related extension methods where an extension property/static member is clearer | Keep public API compatibility and receiver/null semantics; syntax is not a performance claim |
| C# 14 null-conditional assignment | Null guards whose sole purpose is assigning through the checked receiver | Preserve evaluation count and side effects |
| C# 14 span conversions | Array/string/span boundary helpers or avoidable temporary copies | Check overload resolution and lifetime; benchmark allocation-sensitive paths |
| .NET 10 JSON/PipeReader features | Custom input buffering or duplicate-property validation | Preserve wire contracts and streaming/cancellation behavior |
| SDK/Microsoft.Testing.Platform improvements | Legacy test CLI orchestration or custom file-based app launch wrappers | Use the test-platform skill and actual installed runner contract |

Assess newer syntax and APIs even when staying on .NET 10, but implement only approved candidates
with concrete evidence. Keep modernization compatible with every retained asset using the
[library/language matrix](./library-targeting.md).

## Containers and Native AOT

Retain managed .NET 10 templates alongside explicitly selected Native AOT images. Choose the
TFM, SDK, runtime/runtime-deps base and libc/distribution together; compiler/linker dependencies
belong in the builder only. Native AOT requires its own compatibility and real-platform publish
gate, not just `PublishAot=true` or a newer SDK.
