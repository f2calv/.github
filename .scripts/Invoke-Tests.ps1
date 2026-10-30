#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the central repository PowerShell tests.
.DESCRIPTION
    Runs all suites by default or one complete, non-overlapping CI shard.
.PARAMETER TestPath
    Optional Pester test paths. Defaults to root script tests and every skill's scripts/tests directory.
.PARAMETER Shard
    Selects all tests, workspace installation, version preparation, or the remaining suites.
    A named shard cannot be combined with explicit test paths.
.EXAMPLE
    ./.scripts/Invoke-Tests.ps1 -TestPath ./.scripts/tests
.EXAMPLE
    ./.scripts/Invoke-Tests.ps1 -Shard workspace-install
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$TestPath = @(),

    [ValidateSet('all', 'workspace-install', 'version-preparation', 'remaining')]
    [string]$Shard = 'all'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

if ($Shard -ne 'all' -and $TestPath.Count -gt 0) {
    throw 'Select either a CI shard or explicit test paths, not both.'
}

if ($TestPath.Count -eq 0) {
    $TestPath = @(
        Join-Path $PSScriptRoot 'tests'
        Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../.github/skills') -Directory |
        Sort-Object Name |
        ForEach-Object {
            $tests = Join-Path $_.FullName 'scripts/tests'
            if (Test-Path -LiteralPath $tests -PathType Container) { $tests }
        }
    )
}

if ($Shard -ne 'all') {
    $testFiles = @($TestPath | ForEach-Object {
            Get-ChildItem -LiteralPath $_ -Filter '*.Tests.ps1' -File -Recurse
        } | Select-Object -ExpandProperty FullName | Sort-Object -Unique)
    $libraryTests = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../.github/skills/skill-library/scripts/tests'))
    $dedicated = @(
        (Join-Path $libraryTests 'Invoke-WorkspaceInstall.Tests.ps1'),
        (Join-Path $libraryTests 'Invoke-VersionPreparation.Tests.ps1')
    )
    if (@($dedicated | Where-Object { $_ -notin $testFiles }).Count -gt 0) {
        throw 'Dedicated shard test files are missing from central discovery.'
    }
    $TestPath = @(switch ($Shard) {
            'workspace-install' { $dedicated[0] }
            'version-preparation' { $dedicated[1] }
            'remaining' { $testFiles | Where-Object { $_ -notin $dedicated } }
        })
    if ($TestPath.Count -eq 0) { throw 'The selected CI shard contains no test files.' }
    Write-Host "Selected shard '$Shard': $($TestPath.Count) test files."
}

Import-Module Pester -RequiredVersion 5.7.1 -Force

$Configuration = New-PesterConfiguration
$Configuration.Run.Path = $TestPath
$Configuration.Run.Exit = $false
$Configuration.Run.PassThru = $true
$Configuration.Output.Verbosity = 'Detailed'
$Configuration.CodeCoverage.Enabled = $true
$Configuration.CodeCoverage.Path = @(
    (Join-Path $PSScriptRoot '../.github/skills/containers-workflows/scripts/Invoke-Build.ps1'),
    (Join-Path $PSScriptRoot '../.github/skills/containers-workflows/scripts/Invoke-Deploy.ps1'),
    (Join-Path $PSScriptRoot '../.github/skills/containers-workflows/scripts/ContainerWorkflows.Common.ps1')
)
$coverageOutputPath = Join-Path ([IO.Path]::GetTempPath()) "container-workflows-coverage-$PID.xml"
$Configuration.CodeCoverage.OutputPath = $coverageOutputPath

try {
    $result = Invoke-Pester -Configuration $Configuration
    if ($result.Result -ne 'Passed' -or $result.PassedCount -eq 0) { exit 1 }
}
finally {
    Remove-Item -LiteralPath $coverageOutputPath -Force -ErrorAction SilentlyContinue
}
exit 0
