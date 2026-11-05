# Library Targets and Language Versions

Framework retirement is an explicit package-support change, not a side effect of upgrading an
application. Read the actual consumers and package graph, including platform-suffixed projects
and conditional references, before editing target declarations.

## Planned .NET 10/11 Migration

For an approved migration from .NET 8/9/10 libraries to .NET 10/11:

1. Recheck the [support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)
   and release records. As checked 2026-11-05, .NET 8 and 9 reach end of support on **2026-11-10**:
   they are not already unsupported on the assessment date. .NET 10 is LTS through 2028-11-14.
   Do not derive the .NET 11 GA day or lifetime from a release-candidate expiry date.
2. Before .NET 11 GA, keep production .NET 10 targets and prepare the change. Adding a .NET 11
   prerelease target or preview SDK requires explicit prerelease authorization.
3. After GA and dependency/toolchain verification, the selected ordinary class-library matrix is
   `net10.0;net11.0`, replacing `net8.0` and `net9.0`. Applications remain single-targeted.
   Preserve necessary OS suffixes and framework references. Do not retain retired targets merely
   to avoid completing the approved consumer migration.
4. Change the owning imported props/targets, CI test/pack matrices, conditional package groups,
   lock files, container test targets, examples and supported-framework documentation together.
   Inspect evaluated MSBuild output; literal XML searches miss inherited or conditional TFMs.
5. Remove dead target guards and obsolete workarounds when no retained consumer needs them.
   Do not remove independent `netstandard` or platform targets without a separate support decision.
6. Publish producers in dependency order through the release-train skill. Dropping .NET 8/9 package
   assets breaks those consumers; choose the appropriate package release level and migrate them
   deliberately. A successful Debug build using sibling source does not prove NuGet compatibility.

## Compiler Syntax Is Not Runtime API Availability

| Retained targets | Safe baseline | Newer features |
| --- | --- | --- |
| .NET 10 only | Target-default stable C# 14 and .NET 10 APIs | Do not opt into previews just because a newer SDK is installed |
| .NET 10 and 11 | Per-TFM compiler defaults, or an explicitly supported common stable language version | Shared syntax must compile for both; .NET 11-only APIs need a target-specific implementation |
| .NET 11 only, after GA | Target-default stable C# 15 and .NET 11 APIs | Verify each feature is released; language memory-safety previews remain a separate opt-in |

Do not set `LangVersion=latest`/`preview` repository-wide to force C# 15 syntax through .NET 10
assets. A compiler accepting syntax is not evidence that the target/runtime combination is supported.
If shared files must compile as C# 14, do not introduce C# 15-only syntax there. Use narrowly scoped
target-specific files or conditional compilation where justified; avoid duplicating whole classes.

For each modernization, distinguish compiler-only syntax from required runtime/library types,
public metadata, serializer/source-generator support and dependency version. Preserve the shared
public API shape unless a versioned contract change is approved. A .NET 11 optimized path must have
a correct .NET 10 implementation, not a throwing or silently degraded fallback.

## Verification

With execution approval, build/test **both** retained TFMs and relevant Debug/Release graphs.
Inspect the packed `lib/net10.0` and `lib/net11.0` assets and any reference assemblies, and restore
representative consumers from the actual package output/feed. Publish AOT consumers separately
when the library promises AOT compatibility; ordinary unit tests do not establish that promise.
