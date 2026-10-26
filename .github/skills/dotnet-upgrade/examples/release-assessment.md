# Worked Upgrade Assessment

A synthetic .NET 10 application serves HTTP requests and runs a history worker. It uses central
package management, PostgreSQL and a retained .NET 10 library consumer. This is an example of
decision-making and output, not a claim that an upgrade or benchmark has been executed.

## Baseline and Required Changes

The application owns its TFM in `src/Example.App/Example.App.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
</Project>
```

After GA availability and compatible providers are verified, its requested target becomes
`net11.0`. That does not mean every `net10.0` string in the solution should change.

| Surface discovered | Assessment and action |
| --- | --- |
| Application TFM | Raise to `net11.0` after target approval; preserve RID/platform settings. |
| Library with a retained .NET 10 consumer | Preserve `net10.0`; add `net11.0` only when justified. Validate every retained target rather than breaking the consumer for cosmetic alignment. |
| `Directory.Packages.props` | Verify released compatible EF/provider/tool versions from their feeds. Keep unrelated packages on their own version schemes and preserve documented holds. |
| `global.json` selecting Microsoft.Testing.Platform | Keep the runner selection. Do not replace the file with a new SDK-only pin. |
| Container SDK/runtime stages and CI setup | Align their verified available versions while preserving image profile and platforms. One new SDK does not prove the deployed runtime supports the target. |
| Generated lock files | Regenerate through restore; do not replace version strings manually. |
| Central C# instruction still naming a previous language version | Verify the new default, then update the owning rule at a scope compatible with retained TFMs. Do not force all consumers to use newer syntax. |
| Test-platform skill examples using changed CLI options | Verify the installed SDK/runner contract; update the owning examples and validate their affected usage with approval. |

If the target is still RC rather than GA, stop before mutation and offer a readiness assessment
or explicit prerelease adoption. Do not write future stable package versions into configuration.

## Candidate Improvements

Suppose source inspection establishes the following exact call sites. In a real assessment, link
the actual file/symbol and verify the API against the selected release.

| Class | Codebase evidence | Recommendation | Benefit and risk | Verification and source |
| --- | --- | --- | --- | --- |
| Automatic gain | History worker spends time in async processing | Benchmark the new runtime before rewriting await paths | Potential lower runtime overhead; application effect is unmeasured | Equivalent workload and correctness results; [runtime notes](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/runtime) |
| Optional improvement | A parser calls `ToArray()` solely to construct a readable stream | Evaluate a memory-backed stream and its ownership/seek requirements | Potential allocation reduction; buffer lifetime must remain valid | Compare allocated bytes for the same payload and stream contract; [library notes](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/libraries) |
| Optional convention | An internal set initializer needs an ordinal comparer | Consider C# 15 collection expression arguments only where they simplify the existing initialization | Clarity, not an assumed throughput improvement | Equality and duplicate-handling tests; [language guidance](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-15#collection-expression-arguments) |
| Required compatibility | A custom startup validator implements an API marked obsolete in the target | Follow the documented asynchronous replacement and registration rules | Remove obsoletion without duplicate startup validation | Startup success/failure and invocation count; [obsoletions](https://learn.microsoft.com/en-us/dotnet/core/compatibility/core-libraries/11/obsolete-apis) |

The prompt offers **standard upgrade only**, **upgrade plus recommended low-risk improvements**,
or **select individual improvements**. Choosing standard only defers the parser and initializer
changes; it does not authorize ignoring the obsolete implementation or skipping the assessment.

## Honest Completion Report

A useful report distinguishes:

- Platform/package changes and required compatibility fixes.
- Approved source improvements, with before/after measurements only if actually run.
- Deferred candidates and their owning TODO/issue where appropriate.
- Builds, target/configuration coverage and approved tests, with exact outcomes.
- Unverified provider, publish/container or production behavior.
- Related instructions/skills reviewed, updates made and deferred convention decisions.

For example, “Release build passed; parser allocation comparison not run; provider integration
blocked pending isolated database access” is valid. “Upgrade improves performance by 20%” is
not justified by an upstream runtime benchmark or a successful build.
