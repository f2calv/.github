#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Reports configured development container tool versions.
.DESCRIPTION
    Verifies Feature-provided tools without installing packages or initializing a repository.
.PARAMETER PesterVersion
    Exact installed Pester module version to verify.
.PARAMETER Tools
    Executables whose standard --version command must succeed.
.EXAMPLE
    ./Initialize-DevContainer.ps1 -PesterVersion 5.7.1 -Tools git,node
#>
[CmdletBinding()]
param(
    [string]$PesterVersion = '5.7.1',
    [string[]]$Tools = @()
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

function Initialize-DevContainer {
    [CmdletBinding()]
    param(
        [string]$PesterVersion = '5.7.1',
        [string[]]$Tools = @()
    )

    Import-Module Pester -RequiredVersion $PesterVersion -ErrorAction Stop
    Write-Output "PowerShell $($PSVersionTable.PSVersion)"
    Write-Output "Pester $((Get-Module Pester).Version)"
    foreach ($tool in $Tools) {
        & $tool --version
        if ($LASTEXITCODE -ne 0) {
            throw "$tool version check failed with exit code $LASTEXITCODE. Rebuild the development container."
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Initialize-DevContainer -PesterVersion $PesterVersion -Tools $Tools
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Dev Container initialization failed: $($_.Exception.Message)"
        exit 1
    }
}
