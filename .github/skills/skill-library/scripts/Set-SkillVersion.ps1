#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Bumps skill versions and cascades exact pins to the skills that require them.
.DESCRIPTION
Each bump starts from the last released tag, so rerunning it does not bump again. Skills that require a
bumped skill get the new pin and, when already released, a patch bump. Unreleased skills are never
bumped; their first release uses the authored version.
.PARAMETER Id
Skills to bump. Defaults to every released skill changed since its tag without a bump.
.PARAMETER Bump
patch, minor or major.
.EXAMPLE
./.github/skills/skill-library/scripts/Set-SkillVersion.ps1 -Id dotnet-redis -Bump minor
#>
[CmdletBinding()]
param(
    [string[]]$Id = @(),
    [ValidateSet('patch', 'minor', 'major')][string]$Bump = 'patch',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillLibrary.psm1') -Force

$Components = Get-SkillComponent -RepoRoot $RepoRoot
$Errors = @(Test-SkillComponent -RepoRoot $RepoRoot -Component $Components)
if ($Errors.Count) { throw "Invalid skill metadata:`n$($Errors -join "`n")" }
$ById = @{}
foreach ($Component in $Components) { $ById[$Component.Id] = $Component }

function Step-Version([version]$Version, [string]$Level) {
    switch ($Level) {
        'major' { [version]::new($Version.Major + 1, 0, 0) }
        'minor' { [version]::new($Version.Major, $Version.Minor + 1, 0) }
        default { [version]::new($Version.Major, $Version.Minor, $Version.Build + 1) }
    }
}

function Update-Component([object]$Component, [string]$Level, [bool]$Explicit) {
    $Current = ConvertTo-SkillVersion $Component.Version
    $Released = Get-SkillReleasedVersion -RepoRoot $RepoRoot -Id $Component.Id
    if ($null -eq $Released) {
        if ($Explicit) { Write-Warning "$($Component.Id) is unreleased; its first release uses the authored version $Current." }
        return
    }
    $Target = Step-Version $Released $Level
    if ($Target -le $Current) { return }
    Set-SkillMetadataValue -RepoRoot $RepoRoot -Component $Component -Version "$Target"
    $Component.Version = "$Target"
    Write-Host "$($Component.Id): $Current -> $Target"
    foreach ($Dependent in $Components | Where-Object { @($_.Required | ForEach-Object { $_['id'] }) -contains $Component.Id }) {
        Set-SkillMetadataValue -RepoRoot $RepoRoot -Component $Dependent -Version "$Target" -DependencyId $Component.Id
        foreach ($Edge in $Dependent.Required | Where-Object { $_.id -ceq $Component.Id }) { $Edge.version = "$Target" }
        Write-Host "$($Dependent.Id): requires $($Component.Id) $Target"
        Update-Component $Dependent 'patch' $false
    }
}

if ($Id.Count -eq 0) {
    $Id = @(foreach ($Component in $Components) {
            $Released = Get-SkillReleasedVersion -RepoRoot $RepoRoot -Id $Component.Id
            if ($null -ne $Released -and (ConvertTo-SkillVersion $Component.Version) -eq $Released -and
                (Test-SkillChanged -RepoRoot $RepoRoot -Component $Component -Released $Released)) { $Component.Id }
        })
    if ($Id.Count -eq 0) { Write-Host 'No released skill needs a version bump.' }
}
foreach ($Name in $Id) {
    if (-not $ById.ContainsKey($Name)) { throw "Unknown component '$Name'." }
    Update-Component $ById[$Name] $Bump $true
}
