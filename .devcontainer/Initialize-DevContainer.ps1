#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Installs the pinned Specify CLI and reports development container tool versions.
.DESCRIPTION
    Installs Specify through uv for the non-root container user without initializing a repository.
    Python and uv are installed by the Python Feature; Pester by the PowerShell Feature.
.EXAMPLE
    pwsh -NoProfile -File ./.devcontainer/Initialize-DevContainer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

function Initialize-DevContainer {
    [CmdletBinding()]
    param()

    if ($env:SPECIFY_CLI_VERSION -notmatch '^\d+\.\d+\.\d+$') {
        throw 'Set SPECIFY_CLI_VERSION to an exact published version in devcontainer.json.'
    }

    $toolBin = Join-Path $HOME '.local/bin'
    $env:PATH = "$toolBin$([IO.Path]::PathSeparator)$env:PATH"
    uv tool install --force specify-cli --from "git+https://github.com/github/spec-kit.git@v$env:SPECIFY_CLI_VERSION"
    if ($LASTEXITCODE -ne 0) {
        throw "Specify installation failed with exit code $LASTEXITCODE. Check uv and package availability."
    }

    Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
    Write-Output "PowerShell $($PSVersionTable.PSVersion)"
    Write-Output "Pester $((Get-Module Pester).Version)"
    foreach ($tool in @('pre-commit', 'gh', 'node', 'python', 'uv', 'git', 'specify')) {
        [string[]]$arguments = if ($tool -eq 'specify') { @('version') } else { @('--version') }
        & $tool @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$tool version check failed with exit code $LASTEXITCODE. Rebuild the development container."
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Initialize-DevContainer
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Dev Container initialization failed: $($_.Exception.Message)"
        exit 1
    }
}
