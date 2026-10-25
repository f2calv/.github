#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $instructionPath = Join-Path $PSScriptRoot '../../.github/instructions/dotnet.configuration.instructions.md'
    $instructions = Get-Content -LiteralPath $instructionPath -Raw
    $blocks = [regex]::Matches($instructions, '(?ms)^```xml\r?\n(.*?)^```')
    if ($blocks.Count -ne 2) { throw 'Expected the linked and SDK-default appsettings examples.' }
    $linkedItems = $blocks[0].Groups[1].Value
    $defaultItems = $blocks[1].Groups[1].Value
    $PSNativeCommandUseErrorActionPreference = $false

    function Invoke-SyntheticBuild {
        param([string[]]$Arguments)
        $output = & dotnet @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Synthetic MSBuild operation failed: $($output -join "`n")" }
        return $output
    }
}

Describe 'Documented appsettings MSBuild contract' -Tag 'Unit' {
    It 'copies every build input but excludes local publish/package files for <Shape>' -TestCases @(
        @{ Shape = 'linked'; Sdk = 'Microsoft.NET.Sdk'; Kind = 'Content' }
        @{ Shape = 'shared-props'; Sdk = 'Microsoft.NET.Sdk.Web'; Kind = 'Content' }
        @{ Shape = 'none'; Sdk = 'Microsoft.NET.Sdk'; Kind = 'None' }
        @{ Shape = 'web'; Sdk = 'Microsoft.NET.Sdk.Web'; Kind = 'Content' }
        @{ Shape = 'tool'; Sdk = 'Microsoft.NET.Sdk'; Kind = 'None' }
    ) {
        param($Shape, $Sdk, $Kind)
        $root = Join-Path $TestDrive $Shape
        $projectRoot = Join-Path $root 'src/App'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        $sourceRoot = if ($Shape -in @('linked','shared-props')) { $root } else { $projectRoot }
        $items = if ($Shape -in @('linked','shared-props')) { $linkedItems } else { $defaultItems.Replace('<None ', "<$Kind ") }
        $projectItems = $items
        if ($Shape -eq 'shared-props') {
            $props = Join-Path $root 'src/Host.props'
            [IO.File]::WriteAllText($props, "<Project>$($items.Replace('..\..\', '$(MSBuildThisFileDirectory)..\'))</Project>")
            $projectItems = '<Import Project="../Host.props" />'
        }
        foreach ($name in @('appsettings.json','appsettings.Development.json')) {
            [IO.File]::WriteAllText((Join-Path $sourceRoot $name), '{"Mode":"baseline"}')
        }
        # No package sources are needed for this SDK-only synthetic library.
        [IO.File]::WriteAllText((Join-Path $root 'NuGet.config'), '<configuration><packageSources><clear /></packageSources></configuration>')
        $project = Join-Path $projectRoot 'Example.csproj'
        $toolProperties = ''
        if ($Shape -eq 'tool') {
            $toolProperties = '<OutputType>Exe</OutputType><PackAsTool>true</PackAsTool><ToolCommandName>example</ToolCommandName>'
            [IO.File]::WriteAllText((Join-Path $projectRoot 'Program.cs'), 'internal static class Program { private static void Main() { } }')
        }
        [IO.File]::WriteAllText($project, @"
<Project Sdk="$Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <OutputType>Library</OutputType>
    <IsPackable>true</IsPackable>
    <PackageId>Example.ConfigurationFixture</PackageId>
    <Version>1.0.0</Version>
    <NuGetAudit>false</NuGetAudit>
    $toolProperties
  </PropertyGroup>
  $projectItems
</Project>
"@)
        $null = Invoke-SyntheticBuild @('build', $project, '--configuration', 'Release', '--nologo', '-v:q')
        $outputRoot = Join-Path $projectRoot 'bin/Release/net10.0'
        (Join-Path $outputRoot 'appsettings.json') | Should -Exist
        (Join-Path $outputRoot 'appsettings.Local.json') | Should -Not -Exist

        $baseSource = Join-Path $sourceRoot 'appsettings.json'
        [IO.File]::WriteAllText($baseSource, '{"Mode":"new"}')
        [IO.File]::SetLastWriteTimeUtc($baseSource, [datetime]::UtcNow.AddDays(-2))
        [IO.File]::WriteAllText((Join-Path $sourceRoot 'appsettings.Local.json'), '{"PrivateExample":"synthetic"}')
        [IO.File]::WriteAllText((Join-Path $sourceRoot 'appsettings.Local.Development.json'), '{"PrivateExample":"synthetic-dev"}')
        if ($Shape -in @('none','web','tool')) {
            [IO.File]::WriteAllText((Join-Path $sourceRoot 'appsettings.Tests.Local.json'), '{"PrivateExample":"synthetic-test"}')
        }
        $null = Invoke-SyntheticBuild @('build', $project, '--configuration', 'Release', '--no-restore', '--nologo', '-v:q')
        [IO.File]::ReadAllText((Join-Path $outputRoot 'appsettings.json')) | Should -BeExactly '{"Mode":"new"}'
        [IO.File]::ReadAllText((Join-Path $outputRoot 'appsettings.Local.json')) | Should -BeExactly '{"PrivateExample":"synthetic"}'
        (Join-Path $outputRoot 'appsettings.Local.Development.json') | Should -Exist

        $publishRoot = Join-Path $root 'publish'
        $null = Invoke-SyntheticBuild @('publish', $project, '--configuration', 'Release', '--no-restore', '--output', $publishRoot, '--nologo', '-v:q')
        (Join-Path $publishRoot 'appsettings.json') | Should -Exist
        @(Get-ChildItem -LiteralPath $publishRoot -Filter 'appsettings*Local*.json' -File).Count | Should -Be 0

        $packageRoot = Join-Path $root 'packages'
        $null = Invoke-SyntheticBuild @('pack', $project, '--configuration', 'Release', '--no-build', '--output', $packageRoot, '--nologo', '-v:q')
        $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $packageRoot 'Example.ConfigurationFixture.1.0.0.nupkg'))
        try {
            @($zip.Entries | Where-Object { $_.Name -like 'appsettings*Local*.json' }).Count | Should -Be 0
        }
        finally { $zip.Dispose() }
    }
}
