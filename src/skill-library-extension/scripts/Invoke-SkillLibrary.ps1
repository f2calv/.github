#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Searches, installs and loads skills from the skill library catalog through the Specify CLI.
.DESCRIPTION
After every install, upgrade, removal and prune, the helper copies each enabled skill's
resources/.github/ into the workspace .github/, where Copilot discovers skills and instructions.
It records each copy's SHA-256 in .specify/extensions/.skill-library.json and replaces or deletes a
copy only while its bytes still match, so local edits are kept and reported. Spec Kit cannot block
specify extension add, remove, enable or disable on a skill, so every command except help first
warns about skills changed that way since the helper last recorded them. bash/skill-library.sh
and python/skill_library.py implement the same commands, output and state; change all three together.
.PARAMETER Command
help, search, plan, install, upgrade-all, remove, prune, sync, list or load. The helper records
whether each skill was chosen or only required, so prune removes only skills that no chosen skill
requires any more.
.PARAMETER Target
Search terms, or the skill ID for plan, install, remove and load.
.PARAMETER Version
Exact version of the target skill; defaults to the catalog's current version.
.PARAMETER Related
Related skill IDs to install alongside the target, each with its own required skills.
.PARAMETER CatalogUrl
Skill library catalog. Defaults to SKILL_LIBRARY_CATALOG_URL, then the catalog_url packaged in the
extension's skill-library.json by the bootstrap build.
.EXAMPLE
./Invoke-SkillLibrary.ps1 install patterns-ports-and-adapters -Related patterns-modular-monolith
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('help', 'search', 'plan', 'install', 'upgrade-all', 'remove', 'prune', 'sync', 'list', 'load')][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Target = '',
    [string]$Version = '',
    [string[]]$Related = @(),
    [string]$CatalogUrl = ($env:SKILL_LIBRARY_CATALOG_URL ?? ''),
    [string]$Workspace = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$BootstrapId = 'skill'
$Related = @($Related | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $CatalogUrl) {
    $Packaged = Join-Path $PSScriptRoot '../skill-library.json'
    if (Test-Path -LiteralPath $Packaged -PathType Leaf) { $CatalogUrl = [string]((Get-Content -LiteralPath $Packaged -Raw | ConvertFrom-Json -AsHashtable)['catalog_url'] ?? '') }
}

function Get-Catalog {
    if (-not $CatalogUrl) { throw 'No skill library catalog is configured; set SKILL_LIBRARY_CATALOG_URL or reinstall the skill extension.' }
    if (Test-Path -LiteralPath $CatalogUrl -PathType Leaf) { return (Get-Content -LiteralPath $CatalogUrl -Raw | ConvertFrom-Json -AsHashtable).extensions }
    $Response = Invoke-WebRequest -Uri $CatalogUrl -UseBasicParsing
    $Content = if ($Response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($Response.Content) } else { $Response.Content }
    return ($Content | ConvertFrom-Json -AsHashtable).extensions
}

function Get-Installed {
    $Registry = Join-Path $Workspace '.specify/extensions/.registry'
    if (-not (Test-Path -LiteralPath $Registry)) { return @{} }
    return (Get-Content -LiteralPath $Registry -Raw | ConvertFrom-Json -AsHashtable).extensions
}

# Records why each skill was installed and which guidance files were copied; Spec Kit's registry stores only versions.
function Read-State {
    $Path = Join-Path $Workspace '.specify/extensions/.skill-library.json'
    if (-not (Test-Path -LiteralPath $Path)) { return @{ skills = @{}; files = @{} } }
    $Data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $Files = $Data['files'] ?? @{}
    # ConvertFrom-Json parses ISO dates into DateTime; keep the recorded UTC text.
    foreach ($Record in $Files.Values) { if ($Record['copied'] -is [datetime]) { $Record['copied'] = $Record['copied'].ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } }
    return @{ skills = $Data['skills'] ?? @{}; files = $Files }
}

function Get-Manifest { return (Read-State).skills }

function Test-SkillExtension([string]$Id) {
    return $Id -cne $BootstrapId -and (Test-Path -LiteralPath (Join-Path $Workspace ".specify/extensions/$Id/resources/.github") -PathType Container)
}

function Get-OrdinalSet([string[]]$Ids) {
    $Set = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Id in $Ids) { [void]$Set.Add($Id) }
    return , $Set
}

# Records every installed skill with its version and enabled flag, so Show-Drift can spot direct specify changes.
function Save-State([hashtable]$Skills, [hashtable]$Files) {
    $Installed = Get-Installed
    $Ids = Get-OrdinalSet (@($Skills.Keys | Where-Object { $Installed.ContainsKey($_) }) + @($Installed.Keys | Where-Object { Test-SkillExtension $_ }))
    $Kept = [ordered]@{}
    foreach ($Id in $Ids) {
        $Kept[$Id] = [ordered]@{ chosen = (Test-Chosen $Skills $Id); version = [string]$Installed[$Id]['version']; enabled = ($Installed[$Id]['enabled'] -ne $false) }
    }
    $Copies = [ordered]@{}
    foreach ($Rel in @($Files.Keys | Sort-Object)) { $Copies[$Rel] = $Files[$Rel] }
    $Path = Join-Path $Workspace '.specify/extensions/.skill-library.json'
    [IO.File]::WriteAllText($Path, ([ordered]@{ schema_version = '1.2'; skills = $Kept; files = $Copies } | ConvertTo-Json -Depth 5) + "`n")
}

# Spec Kit cannot block direct specify extension commands, so report skills they changed behind the helper's back.
function Show-Drift {
    $Path = Join-Path $Workspace '.specify/extensions/.skill-library.json'
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $Data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $Skills = $Data['skills'] ?? @{}
    # Before schema 1.2 the state did not record every installed skill, so an unrecorded one is not evidence of drift.
    $Complete = $Data['schema_version'] -ceq '1.2'
    $Installed = Get-Installed
    $Lines = foreach ($Id in (Get-OrdinalSet (@($Skills.Keys) + @($Installed.Keys | Where-Object { Test-SkillExtension $_ })))) {
        if (-not $Installed.ContainsKey($Id)) {
            "Warning: $Id was removed outside the skill library. Run install $Id to restore it, or sync to delete its guidance from .github/."
            continue
        }
        $Version = [string]$Installed[$Id]['version']
        $Enabled = $Installed[$Id]['enabled'] -ne $false
        $Entry = $Skills[$Id]
        if ($null -eq $Entry) {
            if ($Complete) { "Warning: $Id $Version was installed outside the skill library. Run sync to copy its guidance into .github/." }
            continue
        }
        if ($Entry.ContainsKey('version') -and [string]$Entry['version'] -cne $Version) {
            "Warning: $Id changed from $($Entry['version']) to $Version outside the skill library. Run sync to update its guidance in .github/."
        }
        if ($Entry.ContainsKey('enabled') -and [bool]$Entry['enabled'] -ne $Enabled) {
            if ($Enabled) { "Warning: $Id was enabled outside the skill library. Run sync to copy its guidance into .github/." }
            else { "Warning: $Id was disabled outside the skill library. Run sync to delete its guidance from .github/." }
        }
    }
    if (@($Lines).Count) {
        $Lines | Write-Output
        Write-Output 'Manage skills with /speckit-skill-library instead of specify extension add, remove, enable or disable.'
    }
}

function Save-Manifest([hashtable]$Skills) { Save-State $Skills (Read-State).files }

function Get-Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Remove-EmptyParent([string]$Path) {
    $Stop = [IO.Path]::GetFullPath((Join-Path $Workspace '.github'))
    $Dir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    while ($Dir -and $Dir.Length -gt $Stop.Length -and -not (Get-ChildItem -LiteralPath $Dir -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $Dir
        $Dir = [IO.Path]::GetDirectoryName($Dir)
    }
}

# Mirrors enabled skills' resources/.github/ into .github/, touching a copy only while it matches its record.
function Sync-Guidance {
    $State = Read-State
    $Records = $State.files
    $Installed = Get-Installed
    $Desired = [ordered]@{}
    $Notes = [Collections.Generic.List[string]]::new()
    foreach ($Id in @($Installed.Keys | Sort-Object)) {
        if ($Id -ceq $BootstrapId -or $Installed[$Id]['enabled'] -eq $false) { continue }
        $Root = Join-Path $Workspace ".specify/extensions/$Id/resources/.github"
        if (-not (Test-Path -LiteralPath $Root -PathType Container)) { continue }
        foreach ($File in Get-ChildItem -LiteralPath $Root -File -Recurse -Force) {
            $Rel = '.github/' + [IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
            $Hash = Get-Sha256 $File.FullName
            if ($Desired.Contains($Rel)) {
                if ($Desired[$Rel].Hash -cne $Hash) { $Notes.Add("Kept $Rel from $($Desired[$Rel].Skill); $Id ships a different copy.") }
                continue
            }
            $Desired[$Rel] = [pscustomobject]@{ Source = $File.FullName; Skill = $Id; Version = [string]$Installed[$Id].version; Hash = $Hash }
        }
    }
    $Next = @{}
    $Counts = @{ copied = 0; updated = 0; removed = 0 }
    foreach ($Rel in $Desired.Keys) {
        $Want = $Desired[$Rel]
        $Path = Join-Path $Workspace $Rel
        $Record = $Records[$Rel]
        $Current = if (Test-Path -LiteralPath $Path -PathType Leaf) { Get-Sha256 $Path } else { $null }
        $NewRecord = [ordered]@{ sha256 = $Want.Hash; skill = $Want.Skill; version = $Want.Version; copied = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
        if ($Current -and $Current -ceq $Want.Hash) {
            $Next[$Rel] = if ($Record -and $Record.sha256 -ceq $Want.Hash) { $Record } else { $NewRecord }
            continue
        }
        if ($Current -and -not $Record) { $Notes.Add("Kept $Rel`: it exists and was not copied by the skill library."); continue }
        if ($Current -and $Current -cne $Record.sha256) {
            $Notes.Add("Kept $Rel`: modified since $($Record.skill) $($Record.version) copied it on $($Record.copied); $($Want.Skill) $($Want.Version) was not applied.")
            $Next[$Rel] = $Record
            continue
        }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
        Copy-Item -LiteralPath $Want.Source -Destination $Path -Force
        $Counts[($Current ? 'updated' : 'copied')]++
        $Next[$Rel] = $NewRecord
    }
    foreach ($Rel in @($Records.Keys | Sort-Object)) {
        if ($Desired.Contains($Rel)) { continue }
        if ($Rel -notlike '.github/*' -or $Rel -match '(^|/)\.\.(/|$)') { continue }
        $Path = Join-Path $Workspace $Rel
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { continue }
        $Record = $Records[$Rel]
        if ((Get-Sha256 $Path) -cne $Record.sha256) {
            $Notes.Add("Kept $Rel`: modified since $($Record.skill) $($Record.version) copied it on $($Record.copied). Review it before deleting it.")
            continue
        }
        Remove-Item -LiteralPath $Path
        Remove-EmptyParent $Path
        $Counts.removed++
    }
    Save-State $State.skills $Next
    Write-Output "Guidance in .github/: $($Counts.copied) copied, $($Counts.updated) updated, $($Counts.removed) removed."
    $Notes | Write-Output
}

function Invoke-Remove([string[]]$Ids) {
    Push-Location -LiteralPath $Workspace
    try {
        foreach ($Id in $Ids) {
            Write-Output "specify extension remove $Id --force"
            & specify extension remove $Id --force
            if ($LASTEXITCODE -ne 0) { throw "Removing $Id failed; skills listed before it were removed." }
        }
    }
    finally { Pop-Location }
    Save-Manifest (Get-Manifest)
}

# Skills installed before the manifest existed count as chosen, so they are never pruned.
function Test-Chosen([hashtable]$Manifest, [string]$Id) {
    if (-not $Manifest.ContainsKey($Id)) { return $true }
    return [bool]$Manifest[$Id].chosen
}

function Get-InstalledRelease([hashtable]$Catalog, [string]$Id, [string]$Installed) {
    try { return Get-Release $Catalog $Id $Installed } catch { return Get-Release $Catalog $Id '' }
}

function Get-Unneeded([hashtable]$Catalog) {
    $Installed = Get-Installed
    $Manifest = Get-Manifest
    $Needed = @{}
    function Add-Needed([string]$Id) {
        if ($Needed.ContainsKey($Id) -or -not $Installed.ContainsKey($Id) -or -not $Catalog.ContainsKey($Id)) { return }
        $Needed[$Id] = $true
        foreach ($Edge in (Get-InstalledRelease $Catalog $Id ([string]$Installed[$Id].version)).Required) { Add-Needed $Edge.id }
    }
    foreach ($Id in $Installed.Keys) { if ($Id -cne $BootstrapId -and (Test-Chosen $Manifest $Id)) { Add-Needed $Id } }
    return @($Installed.Keys | Where-Object { $_ -cne $BootstrapId -and $Catalog.ContainsKey($_) -and -not $Needed.ContainsKey($_) } | Sort-Object)
}

function Show-Unneeded([string[]]$Ids) {
    if (@($Ids).Count) {
        Write-Output "No longer required by any chosen skill: $($Ids -join ', '). Run prune to remove them."
    }
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

function Resolve-Upgrade([hashtable]$Catalog) {
    $Installed = Get-Installed
    $Targets = @{}
    foreach ($Id in $Installed.Keys) {
        if ($Id -cne $BootstrapId -and $Catalog.ContainsKey($Id)) { $Targets[$Id] = Get-Release $Catalog $Id '' }
    }
    $Steps = [Collections.Generic.List[object]]::new()
    $Visited = @{}
    function Add-Step([object]$Release) {
        if ($Visited.ContainsKey($Release.Id)) { return }
        $Visited[$Release.Id] = $true
        foreach ($Edge in $Release.Required) {
            if (-not $Targets.ContainsKey($Edge.id)) { $Targets[$Edge.id] = Get-Release $Catalog $Edge.id $Edge.version }
            if ($Targets[$Edge.id].Version -cne $Edge.version) {
                throw "$($Release.Id) $($Release.Version) requires $($Edge.id) $($Edge.version), but the latest is $($Targets[$Edge.id].Version). Nothing was changed."
            }
            Add-Step $Targets[$Edge.id]
        }
        $Current = if ($Installed.ContainsKey($Release.Id)) { [string]$Installed[$Release.Id].version } else { $null }
        $Action = if ($null -eq $Current) { 'install' }
        elseif ($Current -ceq $Release.Version) { 'current' }
        elseif ([version]$Current -gt [version]$Release.Version) { "newer $Current installed" }
        else { "upgrade from $Current" }
        $Steps.Add([pscustomobject]@{ Id = $Release.Id; Version = $Release.Version; Action = $Action })
    }
    foreach ($Id in @($Targets.Keys | Sort-Object)) { Add-Step $Targets[$Id] }
    return $Steps
}

function Invoke-Specify([object[]]$Steps) {
    $Cache = Join-Path $Workspace ".specify/extensions/.cache/catalog-$(([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($CatalogUrl)))).Substring(0, 16).ToLowerInvariant())"
    Remove-Item -Path "$Cache*.json" -ErrorAction SilentlyContinue
    $env:SPECKIT_CATALOG_URL = $CatalogUrl
    Push-Location -LiteralPath $Workspace
    try {
        foreach ($Step in $Steps) {
            $Arguments = @('extension', 'add', $Step.Id, '--version', $Step.Version)
            if ($Step.Action -like 'upgrade*') { $Arguments += '--force' }
            Write-Output "specify $($Arguments -join ' ')"
            & specify @Arguments
            if ($LASTEXITCODE -ne 0) { throw "Installing $($Step.Id) $($Step.Version) failed; earlier skills in the order remain installed." }
        }
    }
    finally { Pop-Location; Remove-Item Env:SPECKIT_CATALOG_URL -ErrorAction SilentlyContinue }
}

function Assert-Target { if (-not $Target) { throw "The $Command command needs a skill ID." } }

if ($Command -cne 'help') { Show-Drift }

switch ($Command) {
    'help' {
        Write-Output 'Commands: search <terms> | plan <id> | install <id> [-Version X.Y.Z] [-Related a,b] | upgrade-all | remove <id> | prune | sync | list | load <id>'
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
        Invoke-Specify @($Plan.Steps | Where-Object Action -eq 'install')
        $Manifest = Get-Manifest
        foreach ($Step in $Plan.Steps) {
            if ($Step.Reason -in 'requested', 'related, selected') { $Manifest[$Step.Id] = @{ chosen = $true } }
            elseif ($Step.Action -eq 'install' -and -not $Manifest.ContainsKey($Step.Id)) { $Manifest[$Step.Id] = @{ chosen = $false } }
        }
        Save-Manifest $Manifest
        Sync-Guidance
        Write-Output 'Installed. Run plan for newly installed related skills to see their related offers.'
    }
    'upgrade-all' {
        $Catalog = Get-Catalog
        $Steps = @(Resolve-Upgrade $Catalog)
        if ($Steps.Count -eq 0) { Write-Output 'No skills are installed.'; Sync-Guidance; break }
        Write-Output 'Upgrade order:'
        $Steps | Format-Table Id, Version, Action -AutoSize | Out-String -Width 200 | Write-Output
        $Pending = @($Steps | Where-Object { $_.Action -eq 'install' -or $_.Action -like 'upgrade*' })
        if ($Pending.Count -eq 0) { Write-Output 'All installed skills are at their latest versions.' }
        else {
            $Before = Get-Installed
            Invoke-Specify $Pending
            $Manifest = Get-Manifest
            foreach ($Step in $Pending) { if ($Step.Action -eq 'install' -and -not $Manifest.ContainsKey($Step.Id)) { $Manifest[$Step.Id] = @{ chosen = $false } } }
            Save-Manifest $Manifest
            Write-Output "Upgraded $($Pending.Count) skill(s)."
            $Installed = Get-Installed
            $Offers = foreach ($Step in $Pending) {
                $Previous = @()
                if ($Before.ContainsKey($Step.Id)) {
                    try { $Previous = @((Get-Release $Catalog $Step.Id ([string]$Before[$Step.Id].version)).Related | ForEach-Object { $_.id }) } catch { $Previous = @() }
                }
                foreach ($Edge in (Get-Release $Catalog $Step.Id $Step.Version).Related) {
                    if ($Edge.id -notin $Previous -and -not $Installed.ContainsKey($Edge.id)) {
                        [pscustomobject]@{ Id = $Edge.id; OfferedBy = $Step.Id; Reason = $Edge.reason }
                    }
                }
            }
            if (@($Offers).Count) {
                Write-Output 'New related skills you can add with install <id>:'
                $Offers | Sort-Object Id, OfferedBy -Unique | Format-Table Id, OfferedBy, Reason -AutoSize | Out-String -Width 300 | Write-Output
            }
        }
        Sync-Guidance
        Show-Unneeded (Get-Unneeded $Catalog)
    }
    'remove' {
        Assert-Target
        if ($Target -ceq $BootstrapId) { throw "Remove the bootstrap with: specify extension remove $BootstrapId" }
        $Installed = Get-Installed
        if (-not $Installed.ContainsKey($Target)) { throw "'$Target' is not installed." }
        $Catalog = Get-Catalog
        $Dependents = @($Installed.Keys | Where-Object { $_ -cne $BootstrapId -and $_ -cne $Target -and $Catalog.ContainsKey($_) } | Where-Object {
                $Target -cin @((Get-InstalledRelease $Catalog $_ ([string]$Installed[$_].version)).Required | ForEach-Object { $_.id })
            } | Sort-Object)
        if ($Dependents.Count) { throw "'$Target' is required by $($Dependents -join ', '). Remove those first. Nothing was changed." }
        Invoke-Remove @($Target)
        Sync-Guidance
        Show-Unneeded (Get-Unneeded $Catalog)
    }
    'prune' {
        $Unneeded = @(Get-Unneeded (Get-Catalog))
        if ($Unneeded.Count -eq 0) { Write-Output 'Nothing to prune: every installed skill is chosen or required by one.'; break }
        Invoke-Remove $Unneeded
        Write-Output "Removed $($Unneeded.Count) skill(s)."
        Sync-Guidance
    }
    'sync' {
        Sync-Guidance
    }
    'list' {
        $Installed = Get-Installed
        $Manifest = Get-Manifest
        $Rows = foreach ($Pair in $Installed.GetEnumerator() | Sort-Object Key) {
            if ($Pair.Key -cne $BootstrapId -and (Test-Path -LiteralPath (Join-Path $Workspace ".specify/extensions/$($Pair.Key)/resources"))) {
                $Source = if (Test-Chosen $Manifest $Pair.Key) { 'chosen' } else { 'required' }
                [pscustomobject]@{ Id = $Pair.Key; Version = $Pair.Value.version; Enabled = $Pair.Value.enabled; Source = $Source }
            }
        }
        if (@($Rows).Count -eq 0) { Write-Output 'No skills are installed.' }
        else {
            $Rows | Format-Table -AutoSize | Out-String | Write-Output
            Show-Unneeded (Get-Unneeded (Get-Catalog))
        }
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
