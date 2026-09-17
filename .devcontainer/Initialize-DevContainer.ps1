#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Installs the PowerShell test dependency required by the repository.
.DESCRIPTION
    Installs the pinned Pester module and reports the primary tool versions supplied by the
    development container.
.EXAMPLE
    pwsh -NoProfile -File ./.devcontainer/Initialize-DevContainer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

try {
    Install-Module Pester -Scope CurrentUser -RequiredVersion 5.7.1 -Force

    Write-Output "PowerShell $($PSVersionTable.PSVersion)"
    Write-Output "Pester $((Get-Module Pester -ListAvailable | Where-Object Version -EQ '5.7.1' | Select-Object -First 1).Version)"
    pre-commit --version
    gh --version
    node --version

    exit 0
}
catch {
    Write-Error -ErrorAction Continue "Dev Container initialization failed: $($_.Exception.Message)"
    exit 1
}
