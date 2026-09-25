#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the central repository PowerShell tests.
.PARAMETER TestPath
    Optional Pester test paths. Defaults to root script, repository-baseline, container-workflows
    and container-images tests.
.EXAMPLE
    ./.scripts/Invoke-Tests.ps1 -TestPath ./.scripts/tests
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$TestPath = @(
        (Join-Path $PSScriptRoot 'tests'),
        (Join-Path $PSScriptRoot '../.github/skills/repository-baseline/scripts/tests'),
        (Join-Path $PSScriptRoot '../.github/skills/container-workflows/scripts/tests'),
        (Join-Path $PSScriptRoot '../.github/skills/container-images/scripts/tests')
    )
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

Import-Module Pester -RequiredVersion 5.7.1 -Force

$Configuration = New-PesterConfiguration
$Configuration.Run.Path = $TestPath
$Configuration.Run.Exit = $true
$Configuration.Output.Verbosity = 'Detailed'
$Configuration.CodeCoverage.Enabled = $true
$Configuration.CodeCoverage.Path = @(
    (Join-Path $PSScriptRoot '../.github/skills/container-workflows/scripts/Invoke-Build.ps1'),
    (Join-Path $PSScriptRoot '../.github/skills/container-workflows/scripts/Invoke-Deploy.ps1')
)
$coverageOutputPath = Join-Path ([IO.Path]::GetTempPath()) "container-workflows-coverage-$PID.xml"
$Configuration.CodeCoverage.OutputPath = $coverageOutputPath

try {
    Invoke-Pester -Configuration $Configuration
}
finally {
    Remove-Item -LiteralPath $coverageOutputPath -Force -ErrorAction SilentlyContinue
}
