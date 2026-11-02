#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the repository-privacy regression suites.
.DESCRIPTION
    Imports installed Pester 5.7.1 without installing tools and runs the PII scanner and
    attribution cleanup tests against synthetic repositories under Pester's TestDrive.
.EXAMPLE
    ./Invoke-Tests.ps1
.NOTES
    Requires explicit test approval and Git.
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
