#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Builds deterministic Spec Kit extension ZIPs for skills and the bootstrap extension.
.PARAMETER Id
Component IDs to build; defaults to every component.
.PARAMETER OutputDirectory
Directory receiving <id>-<version>.zip files.
.PARAMETER CatalogBaseUrl
Also write catalog.json pointing at the built ZIPs under this URL, for local testing.
.EXAMPLE
./.github/skills/skill-library/scripts/Build-SkillExtension.ps1 -Id docs-adr -OutputDirectory ./artifacts
#>
[CmdletBinding()]
param(
    [string[]]$Id = @(),
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$CatalogBaseUrl = '',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillLibrary.psm1') -Force

$Components = Get-SkillComponent -RepoRoot $RepoRoot
$Errors = @(Test-SkillComponent -RepoRoot $RepoRoot -Component $Components)
if ($Errors.Count) { throw "Invalid skill metadata:`n$($Errors -join "`n")" }
$Unknown = @($Id | Where-Object { $_ -notin $Components.Id })
if ($Unknown.Count) { throw "Unknown component: $($Unknown -join ', ')" }
$Records = @()
foreach ($Component in $Components | Where-Object { $Id.Count -eq 0 -or $_.Id -in $Id }) {
    $Archive = New-SkillExtensionArchive -RepoRoot $RepoRoot -Component $Component -OutputDirectory $OutputDirectory
    $Archive
    if ($CatalogBaseUrl) {
        $Records += [pscustomobject]@{
            Id = $Component.Id; Version = $Component.Version; Url = "$($CatalogBaseUrl.TrimEnd('/'))/$([IO.Path]::GetFileName($Archive.Path))"
            Sha256 = $Archive.Sha256; Required = $Component.Required; Related = $Component.Related
            Description = $Component.Description; Facets = $Component.Facets
        }
    }
}
if ($CatalogBaseUrl) {
    $Catalog = New-SkillCatalog -Release $Records | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'catalog.json'), $Catalog + "`n")
}
