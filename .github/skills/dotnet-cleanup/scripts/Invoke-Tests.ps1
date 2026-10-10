#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
Runs the dotnet-cleanup skill Pester tests.
.PARAMETER TestPath
Optional Pester test path.
.EXAMPLE
./Invoke-Tests.ps1
#>
[CmdletBinding()]
param(
    [string] $TestPath = (Join-Path $PSScriptRoot 'tests')
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

Import-Module Pester -RequiredVersion 5.7.1 -Force
$configuration = New-PesterConfiguration
$configuration.Run.Path = $TestPath
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $configuration
