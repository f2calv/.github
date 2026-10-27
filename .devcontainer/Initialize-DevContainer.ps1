#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Prepares this repository's configured development tools.
.EXAMPLE
    pwsh -NoProfile -File ./.devcontainer/Initialize-DevContainer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

$skillsRoot = Join-Path $PSScriptRoot '../.github/skills'
. (Join-Path $skillsRoot 'containers-devcontainer/scripts/Initialize-DevContainer.ps1')
. (Join-Path $skillsRoot 'spec-kit-bootstrap/scripts/Install-Specify.ps1')

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Install-Specify -Version $env:SPECIFY_CLI_VERSION
        Initialize-DevContainer -PesterVersion '5.7.1' -Tools @('pre-commit', 'gh', 'node', 'python', 'uv', 'git')
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Dev Container initialization failed: $($_.Exception.Message)"
        exit 1
    }
}
