#!/usr/bin/env pwsh
#Requires -Version 7.4

<#+
.SYNOPSIS
Runs the pre-commit management skill's Pester suite.
.DESCRIPTION
Imports the pinned Pester version and returns a nonzero exit code when any test fails.
.EXAMPLE
./Invoke-Tests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
        $result = Invoke-Pester -Path (Join-Path $PSScriptRoot 'tests') -Output Detailed -PassThru
        if ($result.FailedCount -gt 0) {
            exit 1
        }
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue $_
        exit 1
    }
}
