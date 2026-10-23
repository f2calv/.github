# Producer/Consumer Release Example

This synthetic .NET 10 laboratory demonstrates why a successful Debug build does not unlock a
consumer's Release build. It uses two local package IDs and a disposable folder feed; it publishes
nothing and is not a real release train.

## Layout and Reference Selection

```text
fixture/
  producer/
    Directory.Build.props
    Example.Producer.slnx
    src/Example.Core/
    src/Example.Json/
  consumer/
    Directory.Build.props
    Directory.Packages.props
    src/Example.Consumer/
  feed/                       # Generated local packages, not source.
```

Copy the [consumer project](../templates/Example.Consumer.csproj.tmpl) to
`consumer/src/Example.Consumer/Example.Consumer.csproj`, and the
[central package file](../templates/Directory.Packages.props) to
`consumer/Directory.Packages.props`. The project paths assume exactly this sibling layout.
Use the following additional files to make the example buildable.

### `producer/Directory.Build.props`

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <IsPackable>true</IsPackable>
    <Version>1.2.3</Version>
  </PropertyGroup>
</Project>
```

### `producer/Example.Producer.slnx`

```xml
<Solution>
  <Folder Name="/src/">
    <Project Path="src/Example.Core/Example.Core.csproj" />
    <Project Path="src/Example.Json/Example.Json.csproj" />
  </Folder>
</Solution>
```

### `producer/src/Example.Core/Example.Core.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk" />
```

### `producer/src/Example.Core/CountMath.cs`

```csharp
namespace Example.Core;

/// <summary>Provides the synthetic package's counting operation.</summary>
public static class CountMath
{
    /// <summary>Adds one, rejecting integer overflow.</summary>
    /// <param name="value">The initial count.</param>
    /// <returns>The incremented count.</returns>
    public static int Increment(int value) => checked(value + 1);
}
```

### `producer/src/Example.Json/Example.Json.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="../Example.Core/Example.Core.csproj" />
  </ItemGroup>
</Project>
```

### `producer/src/Example.Json/CountJson.cs`

```csharp
using Example.Core;
using System.Text.Json;

namespace Example.Json;

/// <summary>Serializes the synthetic core operation's result.</summary>
public static class CountJson
{
    /// <summary>Increments and serializes a count.</summary>
    /// <param name="value">The initial count.</param>
    /// <returns>The JSON number after incrementing.</returns>
    public static string SerializeNext(int value) => JsonSerializer.Serialize(CountMath.Increment(value));
}
```

### `consumer/Directory.Build.props`

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
</Project>
```

### `consumer/src/Example.Consumer/Program.cs`

```csharp
using Example.Core;
using Example.Json;

if (CountMath.Increment(41) != 42 || CountJson.SerializeNext(41) != "42")
    throw new InvalidOperationException("The consumer did not observe the expected package contract.");

Console.WriteLine("42");
```

Debug selects both producer projects. Every non-Debug configuration selects the two versionless
package references, whose exact versions come from the consumer's central file. The JSON project
also depends on Core, so packing it must retain that dependency rather than embed the sibling's
source.

## Local Validation Sequence

Use a new disposable fixture directory and isolated package-cache directories. Do not delete shared
caches or rely on a cache that may already contain these synthetic versions. These snippets exercise
reference selection, not full repository bootstrapping, licensing or publishing metadata.

With build/pack approval, set local absolute paths and create an empty folder feed:

```powershell
$fixture = '<absolute-fixture-directory>'
$feed = Join-Path $fixture 'feed'
$cache = Join-Path $fixture 'package-cache'
$producer = Join-Path $fixture 'producer/Example.Producer.slnx'
$consumer = Join-Path $fixture 'consumer/src/Example.Consumer/Example.Consumer.csproj'
New-Item -ItemType Directory -Path $feed -Force | Out-Null

dotnet restore $consumer -p:Configuration=Debug --source $feed --packages $cache
if ($LASTEXITCODE -ne 0) { throw 'Debug restore failed.' }
dotnet build $consumer --configuration Debug --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Debug build failed.' }
dotnet restore $consumer -p:Configuration=Release --source $feed --packages $cache
if ($LASTEXITCODE -eq 0) { throw 'An empty feed unexpectedly satisfied Release; check cache isolation.' }
```

The expected failure must name missing `Example.Core` and/or `Example.Json`, not an unrelated SDK
or source-configuration error. Next create the local packages:

```powershell
dotnet pack $producer --configuration Release --no-restore --output $feed
if ($LASTEXITCODE -ne 0) { throw 'Producer packaging failed.' }
dotnet restore $consumer -p:Configuration=Release --source $feed --packages $cache
if ($LASTEXITCODE -ne 0) { throw 'Release restore failed.' }
dotnet build $consumer --configuration Release --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
dotnet run --project $consumer --configuration Release --no-build --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Release consumer failed.' }
```

Require both `Example.Core.1.2.3.nupkg` and `Example.Json.1.2.3.nupkg`, and consumer output `42`.
The prior Debug restore covered the producer projects; the fixture has no configuration-specific
producer dependencies. A real producer with a different Release graph needs its own Release restore.

To model a partial publication, copy only the Core package into a **separate** empty feed and use
another fresh cache. Release restore must fail for the missing Json package. Do not remove or
replace a published version to simulate this case.

## Actual Publication Gate

Local packing proves neither nuget.org publication nor production consumer compatibility.
For a real release, derive the exact version from its immutable release tag and call the existing
[availability helper](../scripts/Test-NuGetPackageAvailability.ps1) in-process:

```powershell
$checker = Join-Path $central '.github/skills/dotnet-release-train/scripts/Test-NuGetPackageAvailability.ps1'
$expectedIds = @('Example.Core', 'Example.Json')
$results = @(& $checker -PackageId $expectedIds -Version $releasedVersion)
if ($LASTEXITCODE -ne 0 -or $results.Count -ne $expectedIds.Count -or
    @($results | Where-Object { -not $_.Available }).Count -gt 0) {
    throw 'Producer publication is incomplete; do not update consumers.'
}
```

Here `$central` is the central checkout and `$releasedVersion` is the observed release version.
Replace the synthetic IDs with the producer's verified package inventory before any approved live
query. Do not invoke this example against NuGet merely to test connectivity.
The helper checks the public restore index; the consuming Release restore/build remains necessary
to prove that package content and dependencies are usable.

| Observed state | Next action |
| --- | --- |
| Producer merged, publication still running | Wait; a merge is not publication |
| One expected package indexed, another missing | Stop downstream changes and investigate publication |
| Every expected ID/version indexed | Update the consumer pins together, then restore/build Release |
| Debug succeeds but Release cannot restore or compile | Stop; fix the package graph or publication, not a fallback to sibling projects |

In a real repository, follow its existing version authority, approvals, checks and release workflow.
Do not copy the fixture's fixed `1.2.3` into a consumer before that version is actually available.
