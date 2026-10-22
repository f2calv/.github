# Minimal MTP and xUnit v3 Setup

This synthetic example joins the runner selection, central properties, packages, solution and
test invocation into one contract. Merge the relevant settings into an existing repository; do
not replace its build properties, package versions or solution wholesale.

The package snapshot uses xUnit v3 `4.0.2` and CodeCoverage `18.12.0` with a stable .NET 10 SDK.
These are reproducible example inputs, not permanent minimums or a claim to be the latest versions.
Resolve compatible stable versions before adoption. Coverage is optional: remove both its central
version and project reference when it is not required.

## Files

Paths below are relative to the example repository root. Add its normal generated EditorConfig,
repository metadata and documentation when adopting it as a real repository.

### `global.json`

```json
{
    "test": {
        "runner": "Microsoft.Testing.Platform"
    }
}
```

### `Directory.Build.props`

```xml
<Project>
  <PropertyGroup>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
</Project>
```

### `Directory.Packages.props`

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="xunit.v3" Version="4.0.2" />
    <PackageVersion Include="Microsoft.Testing.Extensions.CodeCoverage" Version="18.12.0" />
  </ItemGroup>
</Project>
```

### `Example.slnx`

```xml
<Solution>
  <Folder Name="/src/">
    <Project Path="src/Example.Tests/Example.Tests.csproj" />
  </Folder>
</Solution>
```

### `src/Example.Tests/Example.Tests.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <IsTestProject>true</IsTestProject>
    <UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>
    <TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="xunit.v3" />
    <PackageReference Include="Microsoft.Testing.Extensions.CodeCoverage" />
  </ItemGroup>
</Project>
```

### `src/Example.Tests/GlobalUsings.cs`

```csharp
global using Xunit;
```

### `src/Example.Tests/Tests/Unit/CountParsingTests.cs`

```csharp
using System.Globalization;

namespace Example.Tests.Tests.Unit;

[Trait("Category", "Parsing")]
public sealed class CountParsingTests(ITestOutputHelper output)
{
    [Theory]
    [InlineData("42", true, 42)]
    [InlineData("0", true, 0)]
    [InlineData("invalid", false, 0)]
    public void ParseCount(string text, bool expectedSuccess, int expectedValue)
    {
        var success = int.TryParse(text, NumberStyles.Integer,
            CultureInfo.InvariantCulture, out var value);

        output.WriteLine($"Parsed synthetic input successfully: {success}");
        Assert.Equal(expectedSuccess, success);
        Assert.Equal(expectedValue, value);
    }
}
```

## Run and Verify

Ask for test/build approval first. Execute these from the root containing `global.json`, not from
the central skills checkout. An absolute project path does not change SDK/runner discovery:

```powershell
dotnet test --solution Example.slnx
dotnet test --project src/Example.Tests/Example.Tests.csproj --filter-class Example.Tests.Tests.Unit.CountParsingTests
dotnet test --project src/Example.Tests/Example.Tests.csproj --filter-trait "Category=Parsing" --coverage --coverage-output-format cobertura
```

Each command should execute **three cases, three passed, zero failed, zero skipped**. A successful
exit with zero tests is not acceptance. The coverage run must also report an existing, non-empty
Cobertura file; its percentage is not meaningful for this runner-only specimen, which intentionally
has no production assembly. Check diagnostic visibility using the installed runner's help and
verbosity options; do not claim passing-test output is always printed at default verbosity.

In an existing CI test step, set `working-directory` to this same root and use the same native
command. In a VS Code task, use that repository's workspace folder as `options.cwd`; do not assume
the first folder of a multi-root workspace is the test repository.

## Migration Example

| Old surface | Replacement |
| --- | --- |
| `Microsoft.NET.Test.Sdk`, `xunit`, `xunit.runner.visualstudio`, `coverlet.collector` | Versionless references and central package versions shown above |
| Library-shaped test project | All four executable/MTP properties shown above |
| No runner selection | Root `global.json` with MTP selection |
| `dotnet test Example.sln --filter "Category=Parsing"` | `dotnet test --solution Example.slnx --filter-trait "Category=Parsing"` |
| `--collect "XPlat Code Coverage"` | `--coverage --coverage-output-format cobertura` |

Update every actual caller, including editor tasks, reusable workflow inputs and composite-action
steps. Remove obsolete package versions only after their last consumer is gone. Preserve existing
test categories, framework targets, output-helper usage and application-specific setup.

Record the SDK/package versions, exact working directory and commands, executed/pass/fail/skip
counts, output visibility and coverage artifact path. Keep unexecuted checks explicitly pending;
this example's expected counts are not evidence for a consuming repository.
