# HTTP Contract Comparison

A compilable .NET 10 comparison of thin MVC controllers and explicit Minimal API route groups.
Both adapters use the same synthetic widget service; the same black-box tests exercise each host.
This is a bounded investigation fixture, not a production template or application migration.

## Projects

| Project | Purpose |
| --- | --- |
| [Example.Widgets](src/Example.Widgets/README.md) | HTTP-neutral DTOs and a thread-safe synthetic in-memory service |
| [Example.Controllers.SampleApp](src/Example.Controllers.SampleApp/README.md) | Managed MVC baseline with concrete typed results |
| [Example.Minimal.SampleApp](src/Example.Minimal.SampleApp/README.md) | Explicit feature registration, generated request delegates and JSON metadata |
| [Example.HttpContract.Tests](src/Example.HttpContract.Tests/README.md) | One xUnit v3/Microsoft.Testing.Platform HTTP suite for both adapters |

## Build and Test

Use the SDK pinned in [global.json](global.json), .NET 10.0.403. Run commands from this directory.
Package versions are pinned centrally in [Directory.Packages.props](Directory.Packages.props).
The fixture needs no credentials, database, containers or remote application services.

```powershell
dotnet build Example.HttpContract.slnx -c Release
```

With test approval, run the managed comparison. Each case starts a fresh process on a dynamically
allocated loopback port and terminates it after the test. Artifact paths are absolute and supplied
only to the test process; no working-tree configuration changes are required.

```powershell
$previousController = $env:EXAMPLE_CONTROLLER_PATH
$previousMinimal = $env:EXAMPLE_MINIMAL_PATH
try {
    $env:EXAMPLE_CONTROLLER_PATH = (Resolve-Path 'src/Example.Controllers.SampleApp/bin/Release/net10.0/Example.Controllers.SampleApp.dll').Path
    $env:EXAMPLE_MINIMAL_PATH = (Resolve-Path 'src/Example.Minimal.SampleApp/bin/Release/net10.0/Example.Minimal.SampleApp.dll').Path
    dotnet test --project src/Example.HttpContract.Tests/Example.HttpContract.Tests.csproj -c Release --no-build --filter-class Example.HttpContract.Tests.Integration.HttpContractTests
}
finally {
    $env:EXAMPLE_CONTROLLER_PATH = $previousController
    $env:EXAMPLE_MINIMAL_PATH = $previousMinimal
}
```

For manual exploration, run either host with one URL. The first stdout line reports the bound
address after startup. Logging providers are deliberately cleared in this synthetic fixture.

```powershell
dotnet run --project src/Example.Minimal.SampleApp -- --urls http://127.0.0.1:5080
```

Appending `--disable-widgets` disables both feature service registration and route mapping.
These unauthenticated loopback examples must not be exposed as public services.

## HTTP Contract

| Operation | Outcomes checked over HTTP |
| --- | --- |
| `GET /api/v1/widgets/{id:int}` | 200 with camel-case widget JSON; 404 for an absent widget |
| `POST /api/v1/widgets` | 201 with named-route Location that can be followed; 400 with field-keyed validation problems; 409 with a conflict problem |
| `GET /api/v1/widgets/{id:int}/content` | 200 with synthetic attachment headers and bytes; 404 for an absent widget |
| Disabled feature | Lookup route returns 404, not a DI resolution failure |

Invalid and conflict outcomes use `application/problem+json`. The 409 branch uses
`ProblemHttpResult`, with explicit 409 metadata because that result's status is configurable.
This differs deliberately from the [Conflict-shaped JSON example](../typed-outcomes.md).

The singleton service is a locked, in-memory fixture store, not a scoped database service or a
durability example. Creating widgets mutates only that process's memory. Restarting resets it;
there are no update, deletion or remote operations.

## Native Publication

Only the Minimal executable enables `PublishAot`. JSON reflection fallback is disabled even when
running its managed build. Named-route generation uses `RouteValueDictionary`: the anonymous-object
overload triggers IL2026 during .NET 10 trimming analysis.

Native publication requires a supported Windows x64 C++ toolchain and SDK in addition to .NET.
Follow the [Microsoft Native AOT prerequisites](https://learn.microsoft.com/dotnet/core/deploying/native-aot/).
Do not install them or publish without the applicable approval.

```powershell
dotnet publish src/Example.Minimal.SampleApp/Example.Minimal.SampleApp.csproj -c Release -r win-x64 -o artifacts/native
```

After successful publication, rerun the same suite with `EXAMPLE_MINIMAL_PATH` pointing to the
absolute path of `artifacts/native/Example.Minimal.SampleApp.exe`. Keep `EXAMPLE_CONTROLLER_PATH`
pointing to the managed baseline. This exercises the native artifact rather than treating a managed
run as native evidence.

## Evidence and Limits

Verified on 2026-11-07 with SDK 10.0.403, target `net10.0`, and xUnit 4.0.2: Release build succeeded
without warnings; all 18 managed HTTP cases passed, none skipped. Generated request-delegate code
contains all three route mappings. Request, widget, validation-problem and conflict-problem JSON
were exercised with reflection fallback disabled in the Minimal host.

The `win-x64` native attempt resolved compiler package 10.0.14. It first rejected anonymous named-route
values with IL2026; replacing them with a dictionary removed that diagnostic. Publication then
stopped because the platform linker was unavailable. No native executable was produced or tested;
final native compilation and whole-program trimming diagnostics remain unverified.

OpenAPI generation, framework binding/attribute validation, malformed or missing bodies,
authentication, configuration generators, versioning extensions, enum/collection JSON,
incremental streaming, cancellation and disposal under stream failures remain outside this first
fixture slice. The fixed small memory stream proves bytes and headers, not incremental delivery.
FastEndpoints, .NET 11 and startup-performance comparisons remain future investigation work.
