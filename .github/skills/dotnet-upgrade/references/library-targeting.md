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

## Conditional Compatibility

Review source `#if`/`#elif` branches and MSBuild conditions together whenever the target matrix
changes. Compiler symbols describe the compilation target, not the installed SDK or the version
of a referenced NuGet package.

1. For APIs whose availability, signatures or behavior differ between retained frameworks, use
    narrow target-specific preprocessor branches around the affected operation. Preserve the public
    contract, cancellation, disposal and error behavior in every branch. Prefer `NET11_0_OR_GREATER`
    for an implementation valid on .NET 11 and later; use an exact symbol only for a version-specific
    incompatibility. Preserve platform restrictions independently.
2. Re-evaluate every old guard against all retained targets. Remove a wrapper that is always true
    and its dead fallback; remove branches for retired targets. Raise an older `OR_GREATER` guard to
    the oldest retained runtime where it still separates that runtime from `netstandard` or another
    retained target. Do not replace `NET8_0_OR_GREATER` with `NET11_0_OR_GREATER` mechanically: that
    would disable the operation on a retained .NET 10 target. Keep non-version feature/platform
    symbols, and check compound and negated conditions.
3. Evaluate package references and central versions for each retained TFM. Keep exact compatible
    versions in conditioned `PackageVersion` items in `Directory.Packages.props`, and versionless
    references in projects. Condition a `PackageReference` too when only some targets need the
    package, for example when a newer shared framework supplies it. Update or remove retired
    framework conditions and obsolete compatibility references rather than leaving unreachable
    declarations. Preserve documented holds and Debug/Release substitutions.
4. Restore and build every retained target and configuration, then run approved tests that exercise
    each surviving branch. Check the evaluated package graph, not just literal XML or the newest
    target's build. Target-guard cleanup is part of the required migration; optional API adoption
    still needs the upgrade's modernization approval.

### Runtime API Example

For a library retaining `netstandard2.0;net10.0;net11.0`, use the modern stream overload on both
runtime targets, with a correct older-target implementation:

```csharp
private static async Task WritePayloadAsync(
   Stream destination,
   byte[] payload,
   CancellationToken cancellationToken
)
{
#if NET10_0_OR_GREATER
      await destination.WriteAsync(payload.AsMemory(), cancellationToken).ConfigureAwait(false);
#else
      await destination.WriteAsync(payload, 0, payload.Length, cancellationToken).ConfigureAwait(false);
#endif
}
```

After dropping `netstandard2.0` as a separately approved support change, remove the directive and
fallback because every retained target supports the modern overload. A .NET 11-only API instead
needs a `NET11_0_OR_GREATER` branch and a semantically equivalent .NET 10 implementation.

For example, .NET 11 makes Blazor's `EditContext.Validate()` obsolete. In an asynchronous component
handler using matching framework-bound packages, select the supported API for each target:

```csharp
#if NET11_0_OR_GREATER
var valid = await editContext.ValidateAsync(cancellationToken);
#else
cancellationToken.ThrowIfCancellationRequested();
var valid = editContext.Validate();
#endif
if (!valid || cancellationToken.IsCancellationRequested)
   return;
```

Run this inside the handler's busy-state and cancellation lifecycle. Synchronous validators work
on both targets; asynchronous validators require the .NET 11 path. A component targeting only
.NET 11 uses `ValidateAsync` directly, without a dead .NET 10 fallback. A newer SDK alone does not
make this API available when the project still references the .NET 10 package.

### Framework-Bound Package Example

A Razor library retaining .NET 10 and explicitly adopting .NET 11 RC3 can select matching
framework-bound packages centrally:

```xml
<Project>
   <PropertyGroup>
      <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
   </PropertyGroup>
   <ItemGroup Condition="'$(TargetFramework)' == 'net10.0'">
      <PackageVersion Include="Microsoft.AspNetCore.Components.Web" Version="10.0.14" />
   </ItemGroup>
   <ItemGroup Condition="'$(TargetFramework)' == 'net11.0'">
      <PackageVersion Include="Microsoft.AspNetCore.Components.Web" Version="11.0.0-rc.3.26522.148" />
   </ItemGroup>
</Project>
```

The project uses `<PackageReference Include="Microsoft.AspNetCore.Components.Web" />` without a
version. These versions illustrate an approved prerelease migration, not permanent defaults:
verify feed availability and support on each use. For platform-suffixed targets, use the evaluated
framework identifier/version rather than conditions that match only an unsuffixed TFM.

## Verification

If an SDK/TFM change fails in generated source or implicit usings, rebuild the affected project
to regenerate its intermediate files before changing dependencies or adding compatibility code.
Do not edit generated files; distinguish stale output from a current SDK or API incompatibility.

With execution approval, build/test **both** retained TFMs and relevant Debug/Release graphs.
Inspect the packed `lib/net10.0` and `lib/net11.0` assets and any reference assemblies, and restore
representative consumers from the actual package output/feed. Publish AOT consumers separately
when the library promises AOT compatibility; ordinary unit tests do not establish that promise.
