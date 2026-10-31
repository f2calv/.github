#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Searches, installs and loads skills from the skill library catalog through the Specify CLI.
.PARAMETER Command
help, search, plan, install, list or load.
.PARAMETER Target
Search terms, or the skill ID for plan, install and load.
.PARAMETER Version
Exact version of the target skill; defaults to the catalog's current version.
.PARAMETER Related
Related skill IDs to install alongside the target, each with its own required skills.
.PARAMETER CatalogUrl
Skill library catalog; SKILL_LIBRARY_CATALOG_URL overrides the published default.
.EXAMPLE
./Invoke-SkillLibrary.ps1 install patterns-ports-and-adapters -Related patterns-modular-monolith
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('help', 'search', 'plan', 'install', 'list', 'load')][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Target = '',
    [string]$Version = '',
    [string[]]$Related = @(),
    [string]$CatalogUrl = ($env:SKILL_LIBRARY_CATALOG_URL ?? 'https://github.com/f2calv/.github/releases/download/skills-catalog/catalog.json'),
    [string]$Workspace = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$BootstrapId = 'skill'
$Related = @($Related | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Get-Catalog {
    $Response = Invoke-WebRequest -Uri $CatalogUrl -UseBasicParsing
    $Content = if ($Response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($Response.Content) } else { $Response.Content }
    return ($Content | ConvertFrom-Json -AsHashtable).extensions
}

function Get-Installed {
    $Registry = Join-Path $Workspace '.specify/extensions/.registry'
    if (-not (Test-Path -LiteralPath $Registry)) { return @{} }
    return (Get-Content -LiteralPath $Registry -Raw | ConvertFrom-Json -AsHashtable).extensions
}

function Get-Release([hashtable]$Catalog, [string]$Id, [string]$Exact) {
    if (-not $Catalog.ContainsKey($Id)) { throw "Sorry, we can't find the skill '$Id'." }
    $Entry = $Catalog[$Id]
    $Record = if (-not $Exact -or $Exact -ceq $Entry.version) { $Entry }
    elseif ($Entry.ContainsKey('releases') -and $Entry.releases.ContainsKey($Exact)) { $Entry.releases[$Exact] }
    else { throw "Version $Exact of '$Id' is not available." }
    $Library = $Record['skill_library'] ?? @{}
    [pscustomobject]@{
        Id          = $Id
        Version     = if ($Exact) { $Exact } else { $Entry.version }
        Description = $Entry.description
        Required    = @($Library['required'] ?? @())
        Related     = @($Library['related'] ?? @())
    }
}

function Resolve-Plan([hashtable]$Catalog) {
    $Installed = Get-Installed
    $Order = [Collections.Generic.List[object]]::new()
    $Chosen = @{}
    function Add-Skill([string]$Id, [string]$Exact, [string]$Reason) {
        if ($Chosen.ContainsKey($Id)) {
            if ($Exact -and $Chosen[$Id].Version -cne $Exact) { throw "Conflicting versions of '$Id': $($Chosen[$Id].Version) and $Exact." }
            return
        }
        $Release = Get-Release $Catalog $Id $Exact
        $Chosen[$Id] = $Release
        foreach ($Edge in $Release.Required) { Add-Skill $Edge.id $Edge.version "required by $Id" }
        $Current = if ($Installed.ContainsKey($Id)) { $Installed[$Id].version } else { $null }
        $Action = if ($null -eq $Current) { 'install' } elseif ($Current -ceq $Release.Version) { 'installed' } else { "conflict: $Current installed" }
        $Order.Add([pscustomobject]@{ Id = $Id; Version = $Release.Version; Reason = $Reason; Action = $Action })
    }
    Add-Skill $Target $Version 'requested'
    foreach ($Id in $Related) { Add-Skill $Id '' 'related, selected' }
    $Offers = foreach ($Release in $Chosen.Values) {
        foreach ($Edge in $Release.Related) {
            if (-not $Chosen.ContainsKey($Edge.id)) {
                $State = if ($Installed.ContainsKey($Edge.id)) { 'installed' } else { 'not installed' }
                [pscustomobject]@{ Id = $Edge.id; OfferedBy = $Release.Id; Reason = $Edge.reason; State = $State }
            }
        }
    }
    [pscustomobject]@{ Steps = $Order; Offers = @($Offers | Sort-Object Id, OfferedBy -Unique) }
}

function Show-Plan([object]$Plan) {
    Write-Output 'Install order:'
    $Plan.Steps | Format-Table Id, Version, Action, Reason -AutoSize | Out-String -Width 200 | Write-Output
    if ($Plan.Offers.Count) {
        Write-Output 'Related skills you can add with -Related:'
        $Plan.Offers | Format-Table Id, State, OfferedBy, Reason -AutoSize | Out-String -Width 300 | Write-Output
    }
}

function Assert-Target { if (-not $Target) { throw "The $Command command needs a skill ID." } }

switch ($Command) {
    'help' {
        Write-Output 'Commands: search <terms> | plan <id> | install <id> [-Version X.Y.Z] [-Related a,b] | list | load <id>'
    }
    'search' {
        $Terms = @($Target.ToLowerInvariant() -split '\s+' | Where-Object { $_ })
        $Found = foreach ($Pair in (Get-Catalog).GetEnumerator() | Sort-Object Key) {
            if ($Pair.Key -ceq $BootstrapId) { continue }
            $Text = (@($Pair.Key, $Pair.Value.description) + @($Pair.Value['tags'] ?? @())) -join ' '
            if (@($Terms | Where-Object { $Text.ToLowerInvariant() -notlike "*$_*" }).Count -eq 0) {
                [pscustomobject]@{ Id = $Pair.Key; Version = $Pair.Value.version; Facets = (@($Pair.Value['tags'] ?? @()) -join ', '); Description = $Pair.Value.description }
            }
        }
        if (@($Found).Count -eq 0) { Write-Output "Sorry, we can't find a skill matching '$Target'." }
        else { $Found | Format-Table -Wrap -AutoSize | Out-String -Width 300 | Write-Output }
    }
    'plan' {
        Assert-Target
        Show-Plan (Resolve-Plan (Get-Catalog))
    }
    'install' {
        Assert-Target
        $Plan = Resolve-Plan (Get-Catalog)
        Show-Plan $Plan
        $Conflicts = @($Plan.Steps | Where-Object Action -like 'conflict*')
        if ($Conflicts.Count) { throw "Resolve version conflicts first: $($Conflicts.Id -join ', '). Nothing was installed." }
        $Cache = Join-Path $Workspace ".specify/extensions/.cache/catalog-$(([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($CatalogUrl)))).Substring(0, 16).ToLowerInvariant())"
        Remove-Item -Path "$Cache*.json" -ErrorAction SilentlyContinue
        $env:SPECKIT_CATALOG_URL = $CatalogUrl
        Push-Location -LiteralPath $Workspace
        try {
            foreach ($Step in $Plan.Steps | Where-Object Action -eq 'install') {
                Write-Output "specify extension add $($Step.Id) --version $($Step.Version)"
                & specify extension add $Step.Id --version $Step.Version
                if ($LASTEXITCODE -ne 0) { throw "Installing $($Step.Id) $($Step.Version) failed; earlier skills in the order remain installed." }
            }
        }
        finally { Pop-Location; Remove-Item Env:SPECKIT_CATALOG_URL -ErrorAction SilentlyContinue }
        Write-Output 'Installed. Run plan for newly installed related skills to see their related offers.'
    }
    'list' {
        $Installed = Get-Installed
        $Rows = foreach ($Pair in $Installed.GetEnumerator() | Sort-Object Key) {
            if ($Pair.Key -cne $BootstrapId -and (Test-Path -LiteralPath (Join-Path $Workspace ".specify/extensions/$($Pair.Key)/resources"))) {
                [pscustomobject]@{ Id = $Pair.Key; Version = $Pair.Value.version; Enabled = $Pair.Value.enabled }
            }
        }
        if (@($Rows).Count -eq 0) { Write-Output 'No skills are installed.' } else { $Rows | Format-Table -AutoSize | Out-String | Write-Output }
    }
    'load' {
        Assert-Target
        $Root = Join-Path $Workspace ".specify/extensions/$Target/resources"
        if (-not (Test-Path -LiteralPath $Root)) { throw "'$Target' is not installed; run install first." }
        $Files = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | ForEach-Object {
                [IO.Path]::GetRelativePath($Workspace, $_.FullName).Replace('\', '/')
            } | Sort-Object { if ($_ -like '*/SKILL.md') { 0 } elseif ($_ -like '*.instructions.md') { 1 } else { 2 } }, { $_ })
        Write-Output "Installed files for $Target (read SKILL.md first, then instructions, then others as needed):"
        $Files | Write-Output
    }
}
