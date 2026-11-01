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
    foreach ($Link in Get-SkillLink -RepoRoot $RepoRoot -Id $Name) {
        if ($Link.Skill) { if (-not $Related.Contains($Link.Skill)) { $Related[$Link.Skill] = $Link.Source } }
        else { [void]$External.Add($Link.File) }
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
