#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Get-DotNetProjectInventory.ps1') -RepositoryPath $TestDrive
    function New-InventoryFile {
        param([string]$Root, [string]$Relative, [string]$Content)
        $path = Join-Path $Root $Relative
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        [IO.File]::WriteAllText($path, $Content)
    }
}

Describe 'Static project role inventory' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:root | Out-Null
        git -C $script:root init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Synthetic repository initialization failed.' }
    }

    It 'distinguishes executable tests, reusable testing libraries, test hosts and samples' {
        New-InventoryFile $root 'src/Example.Tests/Example.Tests.csproj' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><IsTestProject>true</IsTestProject></PropertyGroup></Project>'
        New-InventoryFile $root 'src/Example.Tests/Tests.cs' 'public class Tests { [Fact] public void Check() {} }'
        New-InventoryFile $root 'src/Example.Testing/Example.Testing.csproj' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><IsPackable>true</IsPackable></PropertyGroup></Project>'
        New-InventoryFile $root 'src/Example.Testing/FakeClient.cs' 'public sealed class FakeClient {}'
        New-InventoryFile $root 'src/Example.TestHost/Example.TestHost.csproj' '<Project Sdk="Microsoft.NET.Sdk.Web" />'
        New-InventoryFile $root 'samples/GenericHost/GenericHost.csproj' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType></PropertyGroup></Project>'
        git -C $root add -- .
        $report = Get-DotNetProjectInventory -RepositoryPath $root
        ($report.Projects | Where-Object Name -eq 'Example.Tests').Role | Should -Be 'test-suite'
        ($report.Projects | Where-Object Name -eq 'Example.Testing').Role | Should -Be 'test-support-library'
        ($report.Projects | Where-Object Name -eq 'Example.TestHost').Role | Should -Be 'integration-test-host'
        ($report.Projects | Where-Object Name -eq 'GenericHost').Role | Should -Be 'sample-application'
        $report.Projects.Count | Should -Be 4
        $report.Projects.ReviewRequired | Should -Not -Contain $false
    }

    It 'records nearest shared properties and conditional uncertainty without executing imports' {
        New-InventoryFile $root 'Directory.Build.props' '<Project><PropertyGroup><IsTestProject>true</IsTestProject></PropertyGroup></Project>'
        New-InventoryFile $root 'src/Directory.Build.props' '<Project><PropertyGroup Condition="false"><OutputType>Exe</OutputType></PropertyGroup><Import Project="$(Unknown)/not-read.props" /></Project>'
        New-InventoryFile $root 'src/Library/Library.csproj' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><IsPackable>false</IsPackable><AssemblyName>Different.Identity</AssemblyName></PropertyGroup></Project>'
        git -C $root add -- .
        $item = (Get-DotNetProjectInventory -RepositoryPath $root).Projects[0]
        $item.Role | Should -Be 'class-library'
        $item.Confidence | Should -Be 'low'
        $item.SharedBuildFiles | Should -Be @('src/Directory.Build.props')
        ($item.Declarations | Where-Object Name -eq 'OutputType').Conditional | Should -BeTrue
        $item.ReviewNotes | Should -Contain 'Import conditions/expressions in src/Directory.Build.props are not evaluated; literal in-repository imports are inspected.'
        @($item.Declarations | Where-Object Name -eq 'IsTestProject').Count | Should -Be 0
    }

    It 'finds backend candidates through direct graph edges and does not infer them from a suffix' {
        New-InventoryFile $root 'src/Host/Host.csproj' '<Project Sdk="Microsoft.NET.Sdk.Web"><ItemGroup><ProjectReference Include="../Domain/Domain.csproj" /></ItemGroup></Project>'
        New-InventoryFile $root 'src/Domain/Domain.csproj' '<Project Sdk="Microsoft.NET.Sdk" />'
        New-InventoryFile $root 'src/Domain/Worker.cs' "/// Summary documentation must not hide code.`npublic class Worker : BackgroundService {}"
        New-InventoryFile $root 'src/Unused.Backend/Unused.Backend.csproj' '<Project Sdk="Microsoft.NET.Sdk" />'
        New-InventoryFile $root 'Example.slnx' '<Solution><Project Path="src/Host/Host.csproj"/><Project Path="src/Domain/Domain.csproj"/></Solution>'
        git -C $root add -- .
        $report = Get-DotNetProjectInventory -RepositoryPath $root
        $domain = $report.Projects | Where-Object Name -eq 'Domain'
        $domain.Role | Should -Be 'backend-library-candidate'
        $domain.ReferencedBy.Count | Should -Be 1
        $domain.Solutions | Should -Be @('Example.slnx')
        ($report.Projects | Where-Object Name -eq 'Unused.Backend').Role | Should -Be 'class-library'
    }

    It 'distinguishes benchmarks and tools from ordinary executables' {
        New-InventoryFile $root 'src/Bench/Bench.csproj' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType></PropertyGroup><ItemGroup><PackageReference Include="BenchmarkDotNet" /></ItemGroup></Project>'
        New-InventoryFile $root 'src/Bench/Bench.cs' 'public class Bench { [Benchmark] public void Run() {} }'
        New-InventoryFile $root 'src/Tool/Tool.csproj' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><PackAsTool>true</PackAsTool></PropertyGroup></Project>'
        git -C $root add -- .
        $report = Get-DotNetProjectInventory -RepositoryPath $root
        ($report.Projects | Where-Object Name -eq 'Bench').Role | Should -Be 'benchmark'
        ($report.Projects | Where-Object Name -eq 'Tool').Role | Should -Be 'cli-tool'
    }

    It 'resolves shared-props reference anchors without joining an absolute path twice' {
        New-InventoryFile $root 'src/Host/Host.csproj' '<Project Sdk="Microsoft.NET.Sdk.Web"><Import Project="../Host.props"/></Project>'
        New-InventoryFile $root 'src/Host.props' '<Project><ItemGroup><ProjectReference Include="$(MSBuildThisFileDirectory)Domain/Domain.csproj"/></ItemGroup></Project>'
        New-InventoryFile $root 'src/Domain/Domain.csproj' '<Project Sdk="Microsoft.NET.Sdk" />'
        New-InventoryFile $root 'src/Domain/Worker.cs' "/// Domain worker.`npublic class Worker : BackgroundService {}"
        git -C $root add -- .
        $report = Get-DotNetProjectInventory -RepositoryPath $root
        $hostProject = $report.Projects | Where-Object Name -eq 'Host'
        $domain = $report.Projects | Where-Object Name -eq 'Domain'
        $hostProject.ProjectReferences[0].ResolvedPath | Should -Be $domain.FullPath
        $domain.Role | Should -Be 'backend-library-candidate'
        $domain.ReferencedBy.Count | Should -Be 1
    }

    It 'does not absorb nested-project source and reports tracked deletions' {
        New-InventoryFile $root 'Parent.csproj' '<Project Sdk="Microsoft.NET.Sdk" />'
        New-InventoryFile $root 'child/Child.csproj' '<Project Sdk="Microsoft.NET.Sdk" />'
        New-InventoryFile $root 'child/FakeClient.cs' 'public class FakeClient {}'
        New-InventoryFile $root 'Gone.csproj' '<Project />'
        git -C $root add -- .
        Remove-Item -LiteralPath (Join-Path $root 'Gone.csproj')
        $report = Get-DotNetProjectInventory -RepositoryPath $root
        ($report.Projects | Where-Object Name -eq 'Parent').SourceFileCount | Should -Be 0
        $report.Repositories[0].MissingTrackedProjects | Should -Be @('Gone.csproj')
    }

    It 'includes non-ignored untracked projects only when requested and handles empty roots' {
        New-InventoryFile $root '.gitignore' 'ignored/'
        New-InventoryFile $root 'New.csproj' '<Project />'
        New-InventoryFile $root 'ignored/Skip.csproj' '<Project />'
        (Get-DotNetProjectInventory -RepositoryPath $root).Projects.Count | Should -Be 0
        $report = Get-DotNetProjectInventory -RepositoryPath @($root,$root) -IncludeUntracked
        $report.Projects.Count | Should -Be 1
        $report.Repositories.Count | Should -Be 1
    }

    It 'rejects malformed project XML instead of emitting a successful default classification' {
        New-InventoryFile $root 'Broken.csproj' '<Project><PropertyGroup>'
        git -C $root add -- .
        { Get-DotNetProjectInventory -RepositoryPath $root } | Should -Throw
    }

    It 'retains transitive backend reachability and incoming references through cycles' {
        New-InventoryFile $root 'Host/Host.csproj' '<Project Sdk="Microsoft.NET.Sdk.Web"><ItemGroup><ProjectReference Include="../First/First.csproj"/></ItemGroup></Project>'
        New-InventoryFile $root 'First/First.csproj' '<Project><ItemGroup><ProjectReference Include="../Second/Second.csproj"/></ItemGroup></Project>'
        New-InventoryFile $root 'First/Worker.cs' 'public class Worker : BackgroundService {}'
        New-InventoryFile $root 'Second/Second.csproj' '<Project><ItemGroup><ProjectReference Include="../First/First.csproj"/></ItemGroup></Project>'
        New-InventoryFile $root 'Second/Worker.cs' 'public class Worker : IBgFeature {}'
        git -C $root add -- .
        $report = Get-DotNetProjectInventory -RepositoryPath $root
        ($report.Projects | Where-Object Name -eq 'First').Role | Should -Be 'backend-library-candidate'
        ($report.Projects | Where-Object Name -eq 'Second').Role | Should -Be 'backend-library-candidate'
        ($report.Projects | Where-Object Name -eq 'First').ReferencedBy.Count | Should -Be 2
    }

    It 'inspects each literal imported document once even when imports form a cycle' {
        New-InventoryFile $root 'Directory.Build.props' '<Project><Import Project="shared.props"/></Project>'
        New-InventoryFile $root 'shared.props' '<Project><Import Project="Directory.Build.props"/><PropertyGroup><AssemblyName>Shared.Identity</AssemblyName></PropertyGroup></Project>'
        New-InventoryFile $root 'Library/Library.csproj' '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType Condition="false">Exe</OutputType></PropertyGroup></Project>'
        git -C $root add -- .
        $item = (Get-DotNetProjectInventory -RepositoryPath $root).Projects[0]
        $item.Role | Should -Be 'class-library'
        $item.Confidence | Should -Be 'low'
        $item.SharedBuildFiles | Should -Be @('Directory.Build.props', 'shared.props')
        @($item.Declarations | Where-Object Name -eq 'AssemblyName').Count | Should -Be 1
    }

    It 'uses test consumers to flag a fixture library without calling it an executable test host' {
        New-InventoryFile $root 'src/Domain.Tests/Domain.Tests.csproj' '<Project><PropertyGroup><IsTestProject>true</IsTestProject></PropertyGroup><ItemGroup><ProjectReference Include="../Domain.Fixtures/Domain.Fixtures.csproj"/></ItemGroup></Project>'
        New-InventoryFile $root 'src/Domain.Fixtures/Domain.Fixtures.csproj' '<Project Sdk="Microsoft.NET.Sdk" />'
        git -C $root add -- .
        $fixture = (Get-DotNetProjectInventory -RepositoryPath $root).Projects | Where-Object Name -eq 'Domain.Fixtures'
        $fixture.Role | Should -Be 'test-support-library'
        $fixture.Confidence | Should -Be 'low'
    }

    It 'reports browser projects separately from server applications and classic solution membership' {
        New-InventoryFile $root 'src/Client/Client.csproj' '<Project Sdk="Microsoft.NET.Sdk.BlazorWebAssembly" />'
        New-InventoryFile $root 'Example.sln' 'Project("{00000000-0000-0000-0000-000000000000}") = "Client", "src\Client\Client.csproj", "{00000000-0000-0000-0000-000000000001}"'
        git -C $root add -- .
        $item = (Get-DotNetProjectInventory -RepositoryPath $root).Projects[0]
        $item.Role | Should -Be 'frontend-client'
        $item.Solutions | Should -Be @('Example.sln')
    }

    It 'rejects DTDs and does not resolve external entities' {
        New-InventoryFile $root 'Unsafe.csproj' '<!DOCTYPE Project [<!ENTITY probe SYSTEM "file:///not-readable">]><Project>&probe;</Project>'
        git -C $root add -- .
        { Get-DotNetProjectInventory -RepositoryPath $root } | Should -Throw
    }

    It 'rejects subdirectory scope and preserves every input byte' {
        New-InventoryFile $root 'src/Library.csproj' '<Project />'
        git -C $root add -- .
        $before = [IO.File]::ReadAllBytes((Join-Path $root 'src/Library.csproj'))
        $null = Get-DotNetProjectInventory -RepositoryPath $root
        [IO.File]::ReadAllBytes((Join-Path $root 'src/Library.csproj')) | Should -Be $before
        { Get-DotNetProjectInventory -RepositoryPath (Join-Path $root 'src') } | Should -Throw '*repository roots*'
    }
}
