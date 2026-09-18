#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Reports the primary tool versions supplied by the development container.
.DESCRIPTION
    Reports the primary tool versions supplied by the development container. Pester is installed
    by the PowerShell Dev Container Feature.
.EXAMPLE
    pwsh -NoProfile -File ./.devcontainer/Initialize-DevContainer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

try {
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
