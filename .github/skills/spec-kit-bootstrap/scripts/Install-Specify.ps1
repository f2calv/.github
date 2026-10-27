#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Installs and verifies an exact Specify CLI release without initializing a repository.
.PARAMETER Version
    Exact published Specify CLI version.
.EXAMPLE
    ./Install-Specify.ps1 -Version 1.2.3
#>
[CmdletBinding()]
param([string]$Version)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

function Install-Specify {
    [CmdletBinding()]
    param([string]$Version)

    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        throw 'Set an exact published Specify CLI version in devcontainer.json.'
    }
    $toolBin = Join-Path $HOME '.local/bin'
    $env:PATH = "$toolBin$([IO.Path]::PathSeparator)$env:PATH"
    uv tool install --force specify-cli --from "git+https://github.com/github/spec-kit.git@v$Version"
    if ($LASTEXITCODE -ne 0) {
        throw "Specify installation failed with exit code $LASTEXITCODE. Check uv and package availability."
    }
    specify version
    if ($LASTEXITCODE -ne 0) {
        throw 'Specify version check failed. Rebuild the development container.'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Install-Specify -Version $Version
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Specify installation failed: $($_.Exception.Message)"
        exit 1
    }
}