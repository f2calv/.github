#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the synthetic file-to-ConfigMap regression suite.
.DESCRIPTION
    Imports installed Pester 5.7.1 without installing tools. Confines disposable
    test files to this skill folder and restores process environment afterward.
.EXAMPLE
    ./Invoke-Tests.ps1
.NOTES
    Requires explicit test approval, Git and Mike Farah yq v4.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

if ($MyInvocation.InvocationName -ne '.') {
    $Work = Join-Path $PSScriptRoot ('..\.test-work\' + [Guid]::NewGuid().ToString('N'))
    $Previous = @{}
    $ExitCode = 1
    try {
        Import-Module Pester -RequiredVersion 5.7.1 -Force
        $null = New-Item -ItemType Directory -Path $Work -Force
        $Work = [IO.Path]::GetFullPath($Work)
        foreach ($Name in @('TEMP', 'TMP', 'TMPDIR')) {
            $Previous[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
            [Environment]::SetEnvironmentVariable($Name, $Work, 'Process')
        }
        $Configuration = New-PesterConfiguration
        $Configuration.Run.Path = Join-Path $PSScriptRoot 'tests'
        $Configuration.Run.PassThru = $true
        $Configuration.Output.Verbosity = 'Detailed'
        $Result = Invoke-Pester -Configuration $Configuration
        if ($Result.FailedCount -eq 0 -and $Result.Result -eq 'Passed') { $ExitCode = 0 }
    }
    catch { Write-Error 'Synthetic regression execution failed. Check installed test prerequisites.' -ErrorAction Continue }
    finally {
        foreach ($Name in $Previous.Keys) {
            [Environment]::SetEnvironmentVariable($Name, $Previous[$Name], 'Process')
        }
        if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
    }
    exit $ExitCode
}
