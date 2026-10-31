#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Publishes every unreleased skill version as GitHub Release <id>/X.Y.Z and refreshes the rolling catalog.
.DESCRIPTION
Runs on the default branch after merge. Published releases are never changed; the catalog asset on the
rolling skills-catalog release is regenerated from all component releases on every run that publishes.
.PARAMETER Repository
owner/name used for release URLs; defaults to GITHUB_REPOSITORY.
.PARAMETER DryRun
Build and report pending releases without creating anything.
.PARAMETER RefreshCatalog
Regenerate the catalog even when nothing new is published.
.EXAMPLE
./.github/skills/skill-library/scripts/Publish-SkillRelease.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [switch]$DryRun,
    [switch]$RefreshCatalog,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path,
    [string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "skill-releases-$PID")
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillLibrary.psm1') -Force
$CatalogTag = 'skills-catalog'
$TagPattern = '^(?<id>[a-z0-9]+(-[a-z0-9]+)*)/(?<version>(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))$'

function Invoke-Gh([string[]]$Arguments) { Invoke-SkillTool gh $Arguments -WorkingDirectory $RepoRoot }

$Components = Get-SkillComponent -RepoRoot $RepoRoot
$Errors = @(Test-SkillComponent -RepoRoot $RepoRoot -Component $Components)
if (-not $Errors.Count) { $Errors = @(Test-SkillVersion -RepoRoot $RepoRoot -Component $Components) }
if ($Errors.Count) { throw "Skill library checks failed:`n$($Errors -join "`n")" }

$Sha = @(Invoke-SkillTool git @('rev-parse', 'HEAD') -WorkingDirectory $RepoRoot)[0]
$Pending = @($Components | Where-Object {
        $Released = Get-SkillReleasedVersion -RepoRoot $RepoRoot -Id $_.Id
        $null -eq $Released -or (ConvertTo-SkillVersion $_.Version) -gt $Released
    })
foreach ($Component in $Pending) {
    $Archive = New-SkillExtensionArchive -RepoRoot $RepoRoot -Component $Component -OutputDirectory $OutputDirectory
    $Tag = "$($Component.Id)/$($Component.Version)"
    Write-Host "$Tag sha256:$($Archive.Sha256)"
    if (-not $DryRun) {
        Invoke-Gh @('release', 'create', $Tag, $Archive.Path, '--target', $Sha, '--title', "$($Component.Id) $($Component.Version)",
            '--notes', "Spec Kit extension for ``$($Component.Id)`` $($Component.Version). Install with ``/speckit-skill-library install $($Component.Id)``.",
            '--latest=false') | Out-Null
    }
}
if ($DryRun) { Write-Host "$($Pending.Count) pending release(s); nothing was published."; return }
if (-not $Pending.Count -and -not $RefreshCatalog) { Write-Host 'Nothing to publish.'; return }
# gh creates tags on GitHub, so fetch them before reading historical metadata.
if (@(Invoke-SkillTool git @('remote') -WorkingDirectory $RepoRoot) -contains 'origin') {
    Invoke-SkillTool git @('fetch', '--quiet', '--tags', 'origin') -WorkingDirectory $RepoRoot | Out-Null
}

$Records = foreach ($Tag in Invoke-Gh @('release', 'list', '--limit', '1000', '--json', 'tagName', '--jq', '.[].tagName')) {
    $Match = [regex]::Match($Tag, $TagPattern)
    if (-not $Match.Success) { continue }
    $Id = $Match.Groups['id'].Value
    $Version = $Match.Groups['version'].Value
    if ($Id -ceq 'skill') {
        $Manifest = ConvertFrom-SkillYaml ((Invoke-SkillTool git @('show', "${Tag}:src/skill-library-extension/extension.yml") -WorkingDirectory $RepoRoot) -join "`n")
        $Metadata = @{}
        $Description = $Manifest.extension.description
    }
    else {
        $Metadata = ConvertFrom-SkillYaml ((Invoke-SkillTool git @('show', "${Tag}:.github/skills/$Id/skill.metadata.yaml") -WorkingDirectory $RepoRoot) -join "`n")
        $Description = (Get-SkillFrontmatter ((Invoke-SkillTool git @('show', "${Tag}:.github/skills/$Id/SKILL.md") -WorkingDirectory $RepoRoot) -join "`n"))['description']
    }
    $Download = Join-Path $OutputDirectory "catalog/$Id/$Version"
    Invoke-Gh @('release', 'download', $Tag, '--pattern', '*.zip', '--dir', $Download, '--clobber') | Out-Null
    $Zip = Get-ChildItem -LiteralPath $Download -Filter '*.zip' | Select-Object -First 1
    $Url = @(Invoke-Gh @('release', 'view', $Tag, '--json', 'assets', '--jq', ".assets[] | select(.name == `"$($Zip.Name)`") | .url"))[0]
    [pscustomobject]@{
        Id = $Id; Version = $Version; Url = $Url; Sha256 = (Get-FileHash -LiteralPath $Zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        Required = @($Metadata['required'] ?? @()); Related = @($Metadata['related'] ?? @()); Description = $Description; Facets = @($Metadata['facets'] ?? @())
    }
}
$CatalogPath = Join-Path $OutputDirectory 'catalog.json'
[IO.File]::WriteAllText($CatalogPath, ((New-SkillCatalog -Release @($Records)) | ConvertTo-Json -Depth 20) + "`n")
Push-Location -LiteralPath $RepoRoot
try { & gh release view $CatalogTag *> $null; $CatalogExists = $LASTEXITCODE -eq 0 }
finally { Pop-Location }
if ($CatalogExists) { Invoke-Gh @('release', 'upload', $CatalogTag, $CatalogPath, '--clobber') | Out-Null }
else {
    Invoke-Gh @('release', 'create', $CatalogTag, $CatalogPath, '--target', $Sha, '--title', 'Skill library catalog',
        '--notes', 'Rolling Spec Kit catalog of every published skill version. The tag never moves; only catalog.json is replaced.', '--latest=false') | Out-Null
}
Write-Host "Published $($Pending.Count) release(s); catalog lists $(@($Records).Count) version(s)."
