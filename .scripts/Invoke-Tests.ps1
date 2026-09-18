#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the central repository PowerShell tests.
.PARAMETER TestPath
    Optional Pester test paths. Defaults to root script and repository-baseline tests.
.EXAMPLE
    ./.scripts/Invoke-Tests.ps1 -TestPath ./.scripts/tests
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$TestPath = @(
        (Join-Path $PSScriptRoot 'tests'),
        (Join-Path $PSScriptRoot '../.github/skills/repository-baseline/scripts/tests')
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

Invoke-Pester -Configuration $Configuration