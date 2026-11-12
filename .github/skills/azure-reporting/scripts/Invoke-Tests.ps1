#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the azure-reporting regression suites.
.DESCRIPTION
    Imports installed Pester 5.7.1 and runs the retail price, model usage and cost summary tests.
    Every Azure call is mocked, so no credentials or network access are needed.
.EXAMPLE
    ./Invoke-Tests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if ($MyInvocation.InvocationName -ne '.') {
    $ExitCode = 1
    try {
        Import-Module Pester -RequiredVersion 5.7.1 -Force
        $Configuration = New-PesterConfiguration
        $Configuration.Run.Path = Join-Path $PSScriptRoot 'tests'
        $Configuration.Run.PassThru = $true
        $Configuration.Output.Verbosity = 'Detailed'
        $Result = Invoke-Pester -Configuration $Configuration
        if ($Result.FailedCount -eq 0 -and $Result.Result -eq 'Passed') { $ExitCode = 0 }
    }
    catch { Write-Error "Regression execution failed: $_" -ErrorAction Continue }
    exit $ExitCode
}
