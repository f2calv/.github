#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the central repository PowerShell tests.
.PARAMETER TestPath
    Optional Pester test paths. Defaults to root script tests and every skill's scripts/tests directory.
.EXAMPLE
    ./.scripts/Invoke-Tests.ps1 -TestPath ./.scripts/tests
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$TestPath = @()
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

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

Import-Module Pester -RequiredVersion 5.7.1 -Force

$Configuration = New-PesterConfiguration
$Configuration.Run.Path = $TestPath
$Configuration.Run.Exit = $true
$Configuration.Output.Verbosity = 'Detailed'
$Configuration.CodeCoverage.Enabled = $true
$Configuration.CodeCoverage.Path = @(
    (Join-Path $PSScriptRoot '../.github/skills/container-workflows/scripts/Invoke-Build.ps1'),
    (Join-Path $PSScriptRoot '../.github/skills/container-workflows/scripts/Invoke-Deploy.ps1'),
    (Join-Path $PSScriptRoot '../.github/skills/container-workflows/scripts/ContainerWorkflows.Common.ps1')
)
$coverageOutputPath = Join-Path ([IO.Path]::GetTempPath()) "container-workflows-coverage-$PID.xml"
$Configuration.CodeCoverage.OutputPath = $coverageOutputPath

try {
    Invoke-Pester -Configuration $Configuration
}
finally {
    Remove-Item -LiteralPath $coverageOutputPath -Force -ErrorAction SilentlyContinue
}
