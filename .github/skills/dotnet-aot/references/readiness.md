# Native AOT Readiness Evidence

Checked 2026-11-05. Reverify versioned documentation before each migration; an unavailable source
is a verification gap, not evidence that a feature is supported.

## Official Sources

| Concern | Authority |
| --- | --- |
| Targets, restrictions and prerequisites | [Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/) |
| Cross-architecture toolchains and cross-OS restriction | [Cross-compilation](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/cross-compile) |
| Library compatibility and analyzers | [AOT-compatible libraries](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/libraries) |
| ASP.NET support matrix and generated endpoints | [ASP.NET Core Native AOT](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/native-aot?view=aspnetcore-10.0) |
| Serialization metadata | [System.Text.Json source generation](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation) |
| EF maturity and query limitations | [EF Native AOT and precompiled queries](https://learn.microsoft.com/en-us/ef/core/performance/nativeaot-and-precompiled-queries) |
| Runtime base variants | [.NET container images](https://learn.microsoft.com/en-us/dotnet/core/docker/container-images) |

Select the exact target ASP.NET documentation version; do not treat a .NET 10 matrix as proof for
.NET 11. Use official tag manifests to verify SDK/runtime-deps images and target platforms.
An optimized AOT base can omit ICU, time-zone data or other dependencies. Choose the appropriate
extra variant or supply dependencies; do not silently enable invariant globalization.

## Scanner Contract

`scripts/Find-AotRisks.ps1` accepts files or directories with `-Path`. It reads C# and MSBuild
source files, including test sources; narrow the input when assessing one executable.
It skips generated/build/vendor directories and directory/file links. Explicit linked inputs
are rejected, rather than silently following them outside the requested tree.

| Parameter | Meaning |
| --- | --- |
| `-Path` | One or more existing files/directories; defaults to the current directory |
| `-Format Object` | Structured PowerShell objects, the default |
| `-Format Json` | Always a JSON array, including zero/one finding |
| `-FailOn Never` | Default: findings do not fail a discovery run |
| `-FailOn Finding` | Exit 2 when manual review candidates exist |

Exit 0 means the scan completed, **not AOT readiness**. Exit 1 means invalid input or a scan failure;
no partial success payload is emitted. Each finding has `Rule`, `Severity` (`review`), `Path`,
`Line` (1-based) and `Message`. Paths identify locations locally; messages never contain source
snippets. Do not upload scan output from a private repository into public issues or external tools.

| Rule | Candidate | Review required |
| --- | --- | --- |
| AOT001 | MVC controllers/registration | Unsupported MVC host surface, or unused/conditional code? |
| AOT002 | Dynamic assembly loading or code generation | Replace runtime generation/loading; inspect reachability |
| AOT003 | Reflection and runtime generic construction | Is the set bounded and preserved by valid annotations/generation? |
| AOT004 | C# dynamic dispatch | Is the runtime binder required on the published path? |
| AOT005 | JSON serialization calls | Are generated context/type-info overloads used, including multiline calls? |
| AOT006 | Configuration binding/validation | Are matching generators active and complete? |
| AOT007 | EF references/query construction | Exact EF/provider AOT support; experimental features need explicit approval |
| AOT008 | Proxy or code-first serialization packages | Inspect the actual package's generation/AOT support |
| AOT009 | Non-generic enum converter | Use generated metadata or `JsonStringEnumConverter<TEnum>` where supported |
| AOT010 | Trimming/AOT suppressions or disabled analysis | Review existing justification; do not hide new diagnostics |
| AOT011 | Hosting features with version-specific support | Check feature matrix and auth schemes for the target release |

This is deliberately lexical triage, not a C# parser or dependency scanner. Comments, strings,
unused code and safe generated-metadata calls can produce false positives. Aliases, split syntax,
reflection wrappers and transitive dependencies can escape detection. Resolve every candidate
against evaluated projects and compiler/publish diagnostics; do not use absence of findings as a gate.

## Native Publish Gate

Record executable, target SDK/TFM/RID, package graph, toolchain and runtime base. Enable AOT in
the executable's selected project/publish profile so restore sees the same settings. With approval:

```text
dotnet publish <executable.csproj> -c Release -f net10.0 -r linux-x64 -p:PublishAot=true
```

Substitute the approved TFM/RID, not just the SDK version. For offline publish, perform a matching
restore first. Do not add `--no-restore` to an unrelated existing restore. Check all trimming/AOT
diagnostics and then run the native output on the real target. Keep warnings visible even when
an upstream dependency blocks adoption; record it as blocked rather than declaring success.
