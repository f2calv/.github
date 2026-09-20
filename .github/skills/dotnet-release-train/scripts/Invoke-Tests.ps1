#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the .NET release train PowerShell tests.
.PARAMETER TestPath
    Optional Pester test path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TestPath = (Join-Path $PSScriptRoot 'tests')
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
