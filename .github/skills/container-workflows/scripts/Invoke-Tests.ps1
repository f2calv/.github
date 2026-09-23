#!/usr/bin/env pwsh
#Requires -Version 7.4
<#!
.SYNOPSIS
    Runs the container workflow Pester suite.
.EXAMPLE
    ./Invoke-Tests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $PSScriptRoot 'tests'
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.CodeCoverage.Enabled = $true
$configuration.CodeCoverage.Path = @(
    (Join-Path $PSScriptRoot 'Invoke-Build.ps1'),
    (Join-Path $PSScriptRoot 'Invoke-Deploy.ps1')
)
$coverageOutputPath = Join-Path ([IO.Path]::GetTempPath()) "container-workflows-coverage-$PID.xml"
$configuration.CodeCoverage.OutputPath = $coverageOutputPath
try {
    Invoke-Pester -Configuration $configuration
}
finally {
    Remove-Item -LiteralPath $coverageOutputPath -Force -ErrorAction SilentlyContinue
}
