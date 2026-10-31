#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Validates every skill sidecar and checks that changed skills have been version-bumped.
.PARAMETER RepoRoot
Repository root; defaults to this script's repository.
.PARAMETER SkipVersionCheck
Validate sidecars only, without comparing against released tags.
.EXAMPLE
./.github/skills/skill-library/scripts/Test-SkillLibrary.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path,
    [switch]$SkipVersionCheck
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillLibrary.psm1') -Force

$Components = Get-SkillComponent -RepoRoot $RepoRoot
$Errors = @(Test-SkillComponent -RepoRoot $RepoRoot -Component $Components)
if (-not $SkipVersionCheck -and $Errors.Count -eq 0) { $Errors = @(Test-SkillVersion -RepoRoot $RepoRoot -Component $Components) }
foreach ($Message in $Errors) { Write-Host "error: $Message" }
if ($Errors.Count) { exit 1 }
Write-Host "$($Components.Count) components are valid."
