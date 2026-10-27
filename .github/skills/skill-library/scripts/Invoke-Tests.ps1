#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Run only the skill-library synthetic metadata and preparation tests after approval.
.DESCRIPTION
Import pinned Pester and run the adjacent suite without provisioning or broad repository tests.
.PARAMETER PythonPath
Existing Python 3.11+ interpreter with PyYAML 6.0.3. Defaults to python3.
.EXAMPLE
./Invoke-Tests.ps1 -PythonPath /path/to/python
.NOTES
Requires separate test execution approval and installed Pester 5.7.1.
#>
[CmdletBinding()]
param([string]$PythonPath = 'python3')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    $PreviousPython = [Environment]::GetEnvironmentVariable('SKILL_LIBRARY_TEST_PYTHON')
    try {
        $env:SKILL_LIBRARY_TEST_PYTHON = $PythonPath
        Import-Module Pester -RequiredVersion 5.7.1
        $Container = New-PesterContainer -Path @(
            (Join-Path $PSScriptRoot 'tests/Invoke-Validation.Tests.ps1'),
            (Join-Path $PSScriptRoot 'tests/Invoke-VersionPreparation.Tests.ps1')
        )
        $Result = Invoke-Pester -Container $Container -Output Normal -PassThru
        if ($Result.FailedCount -gt 0 -or $Result.TotalCount -eq 0) { exit 1 }
        exit 0
    }
    catch {
        Write-Error -Message 'Focused metadata tests failed to run; check installed Pester 5.7.1 and Python/PyYAML prerequisites.' -ErrorAction Continue
        exit 1
    }
    finally {
        [Environment]::SetEnvironmentVariable('SKILL_LIBRARY_TEST_PYTHON', $PreviousPython)
    }
}
#endregion
