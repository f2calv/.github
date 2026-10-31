#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Scaffolds skill.metadata.yaml for skills that do not have one.
.DESCRIPTION
Seeds version 1.0.0, a facet from the folder prefix, related skills from links to other skill folders
and externalFiles from links to other repository files. Review the result: replace generic reasons and
move any genuinely mandatory related skill to required.
.PARAMETER Id
Skill folders to scaffold. Defaults to every skill missing a sidecar.
.EXAMPLE
./.github/skills/skill-library/scripts/New-SkillMetadata.ps1 -Id dotnet-example
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Id = @(),
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillLibrary.psm1') -Force

if ($Id.Count -eq 0) { $Id = @(Get-SkillWithoutMetadata -RepoRoot $RepoRoot) }
foreach ($Name in $Id) {
    $Folder = Join-Path $RepoRoot ".github/skills/$Name"
    $Sidecar = Join-Path $Folder 'skill.metadata.yaml'
    if (-not (Test-Path -LiteralPath (Join-Path $Folder 'SKILL.md'))) { throw "'$Name' has no SKILL.md." }
    if (Test-Path -LiteralPath $Sidecar) { throw "'$Name' already has skill.metadata.yaml." }
    $Related = [ordered]@{}
    $External = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Document in Get-ChildItem -LiteralPath $Folder -Filter '*.md' -Recurse -File | Sort-Object FullName) {
        $Text = [regex]::Replace([IO.File]::ReadAllText($Document.FullName), '(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1\s*$', '')
        foreach ($Match in [regex]::Matches($Text, '\]\(([^)\s#]+)')) {
            $Link = $Match.Groups[1].Value
            if ($Link -match '^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|/)') { continue }
            $Target = [IO.Path]::GetFullPath((Join-Path $Document.DirectoryName ([uri]::UnescapeDataString($Link))))
            $Relative = [IO.Path]::GetRelativePath($RepoRoot, $Target).Replace('\', '/')
            if ($Relative -eq ".github/skills/$Name" -or $Relative.StartsWith(".github/skills/$Name/") -or $Relative.StartsWith('..')) { continue }
            if ($Relative -match '^\.github/skills/([^/]+)') {
                if (-not $Related.Contains($Matches[1])) { $Related[$Matches[1]] = [IO.Path]::GetRelativePath($Folder, $Document.FullName).Replace('\', '/') }
            }
            elseif (Test-Path -LiteralPath $Target -PathType Leaf) { [void]$External.Add($Relative) }
        }
    }
    $Lines = [Collections.Generic.List[string]]::new()
    $Lines.Add('# yaml-language-server: $schema=../skill-library/skill-metadata.schema.json')
    $Lines.Add('version: 1.0.0')
    $Lines.Add("facets: [$($Name.Split('-')[0])]")
    if ($Related.Count) {
        $Lines.Add('related:')
        foreach ($Key in $Related.Keys) { $Lines.Add("  - id: $Key"); $Lines.Add("    reason: Linked from $($Related[$Key]).") }
    }
    if ($External.Count) {
        $Lines.Add('externalFiles:')
        foreach ($Path in $External) { $Lines.Add("  - $Path") }
    }
    if ($PSCmdlet.ShouldProcess($Sidecar, 'Create skill metadata')) {
        [IO.File]::WriteAllText($Sidecar, ($Lines -join "`n") + "`n")
        Write-Host "Created .github/skills/$Name/skill.metadata.yaml"
    }
}
