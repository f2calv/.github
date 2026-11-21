#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

Describe 'Test-DotNetTestConventions' {
    BeforeAll {
        $scriptPath = Join-Path (Split-Path $PSScriptRoot) 'Test-DotNetTestConventions.ps1'
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $root | Out-Null
        git --no-pager -C $root init -q
        if ($LASTEXITCODE) { throw 'Synthetic repository initialization failed.' }
        New-Item -ItemType Directory -Path (Join-Path $root 'Example.Tests/Tests/Integration') | Out-Null
        $file = Join-Path $root 'Example.Tests/Tests/Integration/ContractTests.cs'
    }

    It 'accepts an integration class with a class-level trait' {
        @'
[Trait("Category", "Integration")]
public class ContractTests
{
    [Fact]
    public void Contract() { }
}
'@ | Set-Content -LiteralPath $file
        git --no-pager -C $root -c core.autocrlf=false add -- .
        $report = pwsh -NoProfile -File $scriptPath -RepositoryPath $root -FailOnFindings
        $LASTEXITCODE | Should -Be 0
        $report | Should -BeNullOrEmpty
    }

    It 'reports an unclassified test without failing unless requested' {
        "[Fact]`npublic void Contract() { }" | Set-Content -LiteralPath $file
        git --no-pager -C $root -c core.autocrlf=false add -- .
        (pwsh -NoProfile -Command { & $args[0] -RepositoryPath $args[1] | Select-Object -ExpandProperty Rule } -args $scriptPath, $root) |
            Should -Match 'MissingIntegrationTrait'
        $LASTEXITCODE | Should -Be 0
        pwsh -NoProfile -File $scriptPath -RepositoryPath $root -FailOnFindings | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'accepts a partial class with the integration trait on another declaration' {
        @'
namespace Example;
public partial class ContractTests
{
    [Fact]
    public void Contract() { }
}
'@ | Set-Content -LiteralPath $file
        @'
namespace Example;
[Trait("Category", "Integration")]
public partial class ContractTests { }
'@ | Set-Content -LiteralPath (Join-Path (Split-Path $file) 'ContractTests.Setup.cs')
        git --no-pager -C $root -c core.autocrlf=false add -- .
        $report = pwsh -NoProfile -File $scriptPath -RepositoryPath $root -FailOnFindings
        $LASTEXITCODE | Should -Be 0
        $report | Should -BeNullOrEmpty
    }

    It 'reports a live trait without an integration trait' {
        @'
[Trait("Category", "Live")]
public class ContractTests
{
    [Fact]
    public void Contract() { }
}
'@ | Set-Content -LiteralPath $file
        git --no-pager -C $root -c core.autocrlf=false add -- .
        $rules = pwsh -NoProfile -Command { & $args[0] -RepositoryPath $args[1] | Select-Object -ExpandProperty Rule } -args $scriptPath, $root
        $LASTEXITCODE | Should -Be 0
        $rules | Should -Contain 'LiveWithoutIntegration'
    }
}
