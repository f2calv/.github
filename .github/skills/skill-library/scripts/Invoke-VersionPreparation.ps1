#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Preview or explicitly apply reviewed component version preparation.
.DESCRIPTION
Verify local numeric component tags, compare eligible source inputs and propagate both edge types.
Only version scalars in existing metadata are writable. No tags or other Git objects are created.
.PARAMETER RepoRoot
Absolute repository root, defaulting to the repository containing this script.
.PARAMETER ImpactJson
JSON object mapping every affected released ID to patch, minor or major. No impact is inferred.
.PARAMETER BootstrapId
Explicitly acknowledge unpublished IDs and retain their declared initial versions.
.PARAMETER PythonPath
Existing Python 3.11+ with PyYAML 6.0.3. No installation occurs.
.PARAMETER Apply
Apply only a complete recomputed plan matching ReviewedFingerprint.
.PARAMETER ReviewedFingerprint
Fingerprint returned by the reviewed preview with identical inputs and decisions.
.EXAMPLE
./Invoke-VersionPreparation.ps1 -BootstrapId example-skill -PythonPath /path/to/python
.EXAMPLE
./Invoke-VersionPreparation.ps1 -ImpactJson '{"example-skill":"patch"}'
.EXAMPLE
./Invoke-VersionPreparation.ps1 -ImpactJson '{"example-skill":"patch"}' -Apply -ReviewedFingerprint <hash>
.NOTES
Requires complete local history and release tags; cannot prove that a previously published tag was
not moved or that an unfetched tag exists. Multi-file writes are recoverable, not filesystem-atomic.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'),
    [string]$ImpactJson = '{}',
    [string[]]$BootstrapId = @(),
    [string]$PythonPath = 'python3',
    [switch]$Apply,
    [string]$ReviewedFingerprint = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'Invoke-Validation.ps1') -RepoRoot $RepoRoot -PythonPath $PythonPath
. (Join-Path $PSScriptRoot 'Git-Process.ps1')

#region Functions
function Invoke-PreparationProcess {
    param([string]$Executable, [string[]]$Arguments, [byte[]]$InputBytes)
    $Parameters = @{ Executable = $Executable; Arguments = $Arguments }
    if ($PSBoundParameters.ContainsKey('InputBytes')) { $Parameters['InputBytes'] = $InputBytes }
    $Result = Invoke-LibraryProcess @Parameters
    if ($Result.ExitCode -ne 0) { throw 'Preparation subprocess failed; verify local Git history or Python/PyYAML prerequisites.' }
    return ,$Result.Bytes
}

function Invoke-PreparationGit {
    param([string]$Root, [string[]]$Arguments, [switch]$Bytes)
    $Result = Invoke-LibraryGit -Root $Root -Arguments $Arguments
    if ($Result.ExitCode -ne 0) { throw 'Preparation subprocess failed; verify local Git history or Python/PyYAML prerequisites.' }
    if ($Bytes) { return ,$Result.Bytes }
    return [Text.Encoding]::UTF8.GetString($Result.Bytes).TrimEnd("`n", "`r")
}

function Get-PreparationHash {
    param([byte[]]$Bytes)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Read-PreparationBytes {
    param([string]$Path)
    $Stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $Buffer = [IO.MemoryStream]::new()
    try { $Stream.CopyTo($Buffer); return ,$Buffer.ToArray() }
    finally { $Buffer.Dispose(); $Stream.Dispose() }
}

function Get-PreparationRendering {
    param([string]$Path, [string]$PythonPath, [System.Collections.IDictionary]$Versions)
    $Executable = (Get-Command $PythonPath -CommandType Application -TotalCount 1).Source
    $Json = ConvertTo-Json -InputObject $Versions -Compress -Depth 10
    $Data = Invoke-PreparationProcess -Executable $Executable -Arguments @(
        '-I', '-B', (Join-Path $PSScriptRoot 'Read-Metadata.py'), '--versions-json', $Json
    ) -InputBytes (Read-SkillInputBytes -Path $Path)
    return ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($Data)) -AsHashtable
}

function Get-PreparationTree {
    param([string]$Root, [string]$Revision)
    $Tree = @{}
    $Listing = Invoke-PreparationGit -Root $Root -Arguments @('ls-tree', '-r', '-z', $Revision)
    foreach ($Line in $Listing.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
        $Fields = $Line.Split("`t", 2)
        $Header = $Fields[0].Split(' ')
        $Tree[$Fields[1]] = @{ Mode = $Header[0]; Object = $Header[2] }
    }
    return $Tree
}

function Get-PreparationBaseline {
    param([string]$Root, [string]$Id, [string[]]$Tags, [string]$PythonPath, [string]$Scratch)
    $Latest = $null
    foreach ($Tag in $Tags) {
        if (-not $Tag.StartsWith("$Id/", [StringComparison]::Ordinal)) { continue }
        $Version = $Tag.Substring($Id.Length + 1)
        if ($Version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
            throw "Noncanonical component release tag for $Id; use immutable plain X.Y.Z tags."
        }
        $Commit = Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', '--verify', "$Tag^{commit}")
        [void](Invoke-PreparationGit -Root $Root -Arguments @('merge-base', '--is-ancestor', $Commit, 'HEAD'))
        $Tree = Get-PreparationTree -Root $Root -Revision $Commit
        $IdentityMatches = @()
        foreach ($Path in @($Tree.Keys | Sort-Object)) {
            if ($Path -notmatch '^\.github/skills/[^/]+/skill\.metadata\.yaml$') { continue }
            if ($Tree[$Path].Mode -ne '100644' -and $Tree[$Path].Mode -ne '100755') { throw 'Release metadata must be a regular Git blob.' }
            $Temporary = Join-Path $Scratch 'historical.yaml'
            [IO.File]::WriteAllBytes($Temporary, (Invoke-PreparationGit -Root $Root -Arguments @('cat-file', 'blob', $Tree[$Path].Object) -Bytes))
            $Record = Read-SkillYaml -Path $Temporary -PythonPath $PythonPath
            $Json = ConvertTo-Json -InputObject $Record -Depth 64 -Compress
            if (-not (Test-Json -Json $Json -SchemaFile (Join-Path $PSScriptRoot '../skill-metadata.schema.json') -ErrorAction SilentlyContinue)) {
                throw 'Release metadata schema validation failed; repair release evidence, not the baseline version.'
            }
            if ($Record.id -ceq $Id) { $IdentityMatches += @{ Path = $Path; Record = $Record } }
        }
        if ($IdentityMatches.Count -ne 1 -or $IdentityMatches[0].Record.version -cne $Version) {
            throw "Release tag metadata mismatch or ambiguous identity for $Id."
        }
        if ($null -eq $Latest -or [version]$Version -gt [version]$Latest.Version) {
            $Latest = @{ Version = $Version; Commit = $Commit; Tree = $Tree; Path = $IdentityMatches[0].Path; Record = $IdentityMatches[0].Record }
        }
    }
    return $Latest
}

function Get-PreparationInventory {
    param(
        [string]$Root, [string]$Folder, [hashtable]$Record, [hashtable]$Defaults,
        [string[]]$Eligible, [hashtable]$Tree, [string]$PythonPath, [string]$Scratch
    )
    $Inventory = [ordered]@{}
    $Paths = @($Eligible | Where-Object { $_.StartsWith("$Folder/", [StringComparison]::Ordinal) })
    $Paths += '.config/skill-library.yaml'
    $Paths += @($Defaults.notices)
    if ($Record.ContainsKey('notices')) { $Paths += @($Record.notices) }
    if ($Record.ContainsKey('externalFiles')) { $Paths += @($Record.externalFiles | ForEach-Object { $_.path }) }
    foreach ($Path in @($Paths | Sort-Object -Unique)) {
        $Key = if ($Path.StartsWith("$Folder/", [StringComparison]::Ordinal)) { 'internal/' + $Path.Substring($Folder.Length + 1) } else { "repository/$Path" }
        if ($null -ne $Tree) {
            if (-not $Tree.ContainsKey($Path) -or $Tree[$Path].Mode -notin @('100644', '100755')) { throw 'Released input is missing or not a regular Git blob.' }
            $Data = Invoke-PreparationGit -Root $Root -Arguments @('cat-file', 'blob', $Tree[$Path].Object) -Bytes
            $Mode = $Tree[$Path].Mode
        }
        else {
            if ($Path -notin $Eligible) { throw 'Declared preparation input must be tracked or new and nonignored.' }
            $FullPath = Assert-LibraryPath -Root $Root -Relative $Path
            $Data = Read-PreparationBytes $FullPath
            $Mode = if (-not $IsWindows -and ([IO.File]::GetUnixFileMode($FullPath) -band [IO.UnixFileMode]::UserExecute)) { '100755' } else { '100644' }
        }
        if ($Path -ceq "$Folder/skill.metadata.yaml") {
            $Temporary = Join-Path $Scratch 'normalize.yaml'
            [IO.File]::WriteAllBytes($Temporary, $Data)
            $Rendered = Get-PreparationRendering -Path $Temporary -PythonPath $PythonPath -Versions @{}
            $Data = [Convert]::FromBase64String($Rendered.normalized)
        }
        $Inventory[$Key] = "$Mode/$(Get-PreparationHash $Data)"
    }
    return $Inventory
}

function Set-PreparationBytes {
    param([IO.FileStream]$Stream, [byte[]]$Bytes)
    $Stream.Position = 0
    $Stream.Write($Bytes, 0, $Bytes.Length)
    $Stream.SetLength($Bytes.Length)
    $Stream.Flush($true)
}

function Get-PreparationSourceState {
    param([string]$Root, [object]$Validated)
    $Paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$Paths.Add('.config/skill-library.yaml')
    foreach ($Notice in $Validated.Defaults.notices) { [void]$Paths.Add($Notice) }
    foreach ($Record in $Validated.Catalog.Values) {
        foreach ($Notice in $Record.notices) { [void]$Paths.Add($Notice) }
        foreach ($External in $Record.externalFiles) { [void]$Paths.Add($External.path) }
    }
    $EligibleText = Invoke-PreparationGit -Root $Root -Arguments @('ls-files', '--cached', '--others', '--exclude-standard', '-z')
    foreach ($Path in $EligibleText.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
        if ($Path -match '^(\.github/skills/[^/]+)/' -and (Test-Path -LiteralPath (Join-Path $Root "$($Matches[1])/skill.metadata.yaml"))) {
            if (Test-Path -LiteralPath (Join-Path $Root $Path) -PathType Leaf) { [void]$Paths.Add($Path) }
        }
    }
    $Inputs = [ordered]@{}
    $Modes = [ordered]@{}
    foreach ($Path in @($Paths | Sort-Object)) {
        $FullPath = Assert-LibraryPath -Root $Root -Relative $Path
        $Inputs[$Path] = Get-PreparationHash (Read-PreparationBytes $FullPath)
        $Modes[$Path] = if ($IsWindows) { 'windows' } else { [int][IO.File]::GetUnixFileMode($FullPath) }
    }
    $Implementation = [ordered]@{}
    foreach ($File in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..') -Recurse -File -Force | Sort-Object FullName) {
        if ($File.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Preparation implementation cannot contain symbolic links.' }
        $Implementation[[IO.Path]::GetRelativePath((Join-Path $PSScriptRoot '..'), $File.FullName)] = Get-PreparationHash (Read-PreparationBytes $File.FullName)
    }
    return [ordered]@{
        Root = $Root; Head = (Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', '--verify', 'HEAD'))
        Refs = (Invoke-PreparationGit -Root $Root -Arguments @('show-ref', '--head'))
        Index = (Invoke-PreparationGit -Root $Root -Arguments @('ls-files', '--stage', '-z'))
        Inputs = $Inputs; Modes = $Modes; Implementation = $Implementation
    }
}

function Invoke-SkillVersionPreparation {
    param(
        [string]$RepoRoot, [string]$ImpactJson = '{}', [string[]]$BootstrapId = @(),
        [string]$PythonPath = 'python3', [switch]$Apply, [string]$ReviewedFingerprint = ''
    )
    $Root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $Scratch = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $RetainScratch = $false
    [void][IO.Directory]::CreateDirectory($Scratch)
    try {
        $Ancestor = [IO.DirectoryInfo]::new($Root)
        while ($null -ne $Ancestor) {
            if ($Ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Repository ancestors must not be symbolic links.' }
            $Ancestor = $Ancestor.Parent
        }
        $Validated = Invoke-SkillValidation -RepoRoot $Root -PythonPath $PythonPath -IncludeCatalog
        $SourceBefore = Get-PreparationSourceState -Root $Root -Validated $Validated
        $Validated = Invoke-SkillValidation -RepoRoot $Root -PythonPath $PythonPath -IncludeCatalog
        if ((Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', '--show-toplevel')) -cne $Root) { throw 'Use the actual repository root, not a nested folder.' }
        if ((Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', '--is-shallow-repository')) -ne 'false') { throw 'Shallow history is unsafe for version preparation; provide complete history.' }
        $GitDirectory = Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', '--absolute-git-dir')
        foreach ($Unsafe in @('shallow', 'info/grafts', 'objects/info/alternates')) {
            if (Test-Path -LiteralPath (Join-Path $GitDirectory $Unsafe)) { throw 'Incomplete or redirected Git history is unsafe for version preparation.' }
        }
        if (Invoke-PreparationGit -Root $Root -Arguments @('replace', '-l')) { throw 'Replacement Git history is unsafe for version preparation.' }
        $Configuration = Invoke-PreparationGit -Root $Root -Arguments @('config', '--list')
        if ($Configuration -match '(?im)^(extensions\.partialclone|remote\..+\.promisor)=') { throw 'Partial Git history is unsafe for version preparation.' }
        if (Invoke-PreparationGit -Root $Root -Arguments @('ls-files', '--unmerged')) { throw 'Resolve unmerged index entries before preparation.' }
        $Head = Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', '--verify', 'HEAD')
        $TagsText = Invoke-PreparationGit -Root $Root -Arguments @('tag', '--list')
        $Tags = @($TagsText.Split("`n", [StringSplitOptions]::RemoveEmptyEntries))
        $EligibleText = Invoke-PreparationGit -Root $Root -Arguments @('ls-files', '--cached', '--others', '--exclude-standard', '-z')
        $Eligible = @($EligibleText.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries) | Sort-Object -Unique |
            Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf })
        $Impact = ConvertFrom-Json -InputObject $ImpactJson -AsHashtable
        if ($Impact -isnot [System.Collections.IDictionary]) { throw 'ImpactJson must be an object mapping IDs to patch, minor or major.' }
        foreach ($Id in $Impact.Keys) {
            if (-not $Validated.Catalog.ContainsKey($Id) -or $Impact[$Id] -cnotin @('patch', 'minor', 'major')) { throw 'Unknown ID or invalid explicit impact decision.' }
        }
        foreach ($Id in $BootstrapId) { if (-not $Validated.Catalog.ContainsKey($Id)) { throw 'Unknown bootstrap ID.' } }
        $Entries = [ordered]@{}
        $Folders = @{}
        foreach ($Name in $Validated.Folders.Keys) { $Folders[$Validated.Folders[$Name]] = ".github/skills/$Name" }
        foreach ($Id in @($Validated.Catalog.Keys | Sort-Object)) {
            $Folder = $Folders[$Id]
            $Record = $Validated.Catalog[$Id]
            $Baseline = Get-PreparationBaseline -Root $Root -Id $Id -Tags $Tags -PythonPath $PythonPath -Scratch $Scratch
            $Current = Get-PreparationInventory -Root $Root -Folder $Folder -Record $Record -Defaults $Validated.Defaults -Eligible $Eligible -PythonPath $PythonPath -Scratch $Scratch
            $Reasons = [Collections.Generic.List[string]]::new()
            if ($null -eq $Baseline) { $Reasons.Add('unpublished initial release intent') }
            else {
                $HistoricalDefaultsPath = '.config/skill-library.yaml'
                if (-not $Baseline.Tree.ContainsKey($HistoricalDefaultsPath)) { throw 'Released repository defaults are missing.' }
                $Temporary = Join-Path $Scratch 'defaults.yaml'
                [IO.File]::WriteAllBytes($Temporary, (Invoke-PreparationGit -Root $Root -Arguments @('cat-file', 'blob', $Baseline.Tree[$HistoricalDefaultsPath].Object) -Bytes))
                $HistoricalDefaults = Read-SkillYaml -Path $Temporary -PythonPath $PythonPath
                if (-not (Test-Json -Json (ConvertTo-Json $HistoricalDefaults -Depth 64) -SchemaFile (Join-Path $PSScriptRoot '../repository-defaults.schema.json') -ErrorAction SilentlyContinue)) { throw 'Released repository defaults schema validation failed.' }
                if (-not $HistoricalDefaults.ContainsKey('notices')) { $HistoricalDefaults['notices'] = @() }
                $OldFolder = $Baseline.Path.Substring(0, $Baseline.Path.LastIndexOf('/'))
                $Old = Get-PreparationInventory -Root $Root -Folder $OldFolder -Record $Baseline.Record -Defaults $HistoricalDefaults -Eligible @($Baseline.Tree.Keys) -Tree $Baseline.Tree -PythonPath $PythonPath -Scratch $Scratch
                foreach ($Key in @(@($Current.Keys) + @($Old.Keys) | Sort-Object -Unique)) {
                    if (-not $Current.Contains($Key) -or -not $Old.Contains($Key) -or $Current[$Key] -cne $Old[$Key]) { $Reasons.Add("content: $Key") }
                }
                if ($OldFolder -cne $Folder) { $Reasons.Add('stable-ID source/native move') }
            }
            $Entries[$Id] = @{ Record = $Record; Baseline = $Baseline; Reasons = $Reasons; Folder = $Folder; Target = $null }
        }
        do {
            $Changed = $false
            foreach ($Id in $Entries.Keys) {
                foreach ($Edge in @($Entries[$Id].Record.required) + @($Entries[$Id].Record.optional)) {
                    if ($Entries[$Edge.id].Reasons.Count -gt 0) {
                        $Reason = "dependency: $($Edge.id)"
                        if (-not $Entries[$Id].Reasons.Contains($Reason)) { $Entries[$Id].Reasons.Add($Reason); $Changed = $true }
                    }
                }
            }
        } while ($Changed)
        $Missing = [Collections.Generic.List[string]]::new()
        $Versions = [ordered]@{}
        foreach ($Id in $Entries.Keys) {
            $Entry = $Entries[$Id]
            if ($null -eq $Entry.Baseline) {
                if ($Id -notin $BootstrapId) { $Missing.Add("bootstrap: $Id") }
                if ($Impact.ContainsKey($Id)) { throw "Unpublished $Id retains its explicit initial version; use BootstrapId, not impact." }
                $Entry.Target = $Entry.Record.version
            }
            elseif ($Entry.Reasons.Count -gt 0) {
                if ($Id -in $BootstrapId) { throw "Released $Id cannot bootstrap." }
                if (-not $Impact.ContainsKey($Id)) { $Missing.Add("impact: $Id"); continue }
                $Version = [version]$Entry.Baseline.Version
                $Entry.Target = switch ($Impact[$Id]) {
                    'major' { "$($Version.Major + 1).0.0" }
                    'minor' { "$($Version.Major).$($Version.Minor + 1).0" }
                    'patch' { "$($Version.Major).$($Version.Minor).$($Version.Build + 1)" }
                }
            }
            else {
                if ($Impact.ContainsKey($Id) -or $Id -in $BootstrapId) { throw "Unchanged released $Id has no release impact to decide." }
                $Entry.Target = $Entry.Baseline.Version
            }
            if ($null -ne $Entry.Baseline -and $Entry.Record.version -cne $Entry.Baseline.Version -and $Entry.Record.version -cne $Entry.Target) {
                throw "Unexplained own-version drift for $Id; expected released baseline or the explicitly decided target."
            }
            $Versions[$Id] = $Entry.Target
        }
        $Changes = [Collections.Generic.List[object]]::new()
        $Candidates = [Collections.Generic.List[object]]::new()
        $Components = @(
            foreach ($Id in $Entries.Keys) {
                $Entry = $Entries[$Id]
                $Path = "$($Entry.Folder)/skill.metadata.yaml"
                if ($Missing.Count -eq 0) {
                    foreach ($Kind in @('required', 'optional')) {
                        foreach ($Edge in $Entry.Record[$Kind]) {
                            $Allowed = @($Versions[$Edge.id])
                            if ($null -ne $Entries[$Edge.id].Baseline) { $Allowed += $Entries[$Edge.id].Baseline.Version }
                            if ($Edge.version -cnotin $Allowed) { throw "Unexplained dependency pin drift for $Id." }
                            if ($Edge.version -cne $Versions[$Edge.id]) { $Changes.Add([ordered]@{ Path = $Path; Field = "$Kind/$($Edge.id)/version"; From = $Edge.version; To = $Versions[$Edge.id] }) }
                        }
                    }
                    if ($Entry.Record.version -cne $Entry.Target) { $Changes.Add([ordered]@{ Path = $Path; Field = 'version'; From = $Entry.Record.version; To = $Entry.Target }) }
                    $Original = Read-PreparationBytes (Join-Path $Root $Path)
                    $Rendered = Get-PreparationRendering -Path (Join-Path $Root $Path) -PythonPath $PythonPath -Versions $Versions
                    $Proposed = [Convert]::FromBase64String($Rendered.bytes)
                    if ((Get-PreparationHash $Original) -cne (Get-PreparationHash $Proposed)) { $Candidates.Add(@{ Path = $Path; Original = $Original; Proposed = $Proposed; Completed = $false }) }
                }
                [ordered]@{
                    Id = $Id; Path = $Path; Baseline = $(if ($null -ne $Entry.Baseline) { $Entry.Baseline.Version } else { $null })
                    BaselineCommit = $(if ($null -ne $Entry.Baseline) { $Entry.Baseline.Commit } else { $null })
                    Target = $Entry.Target; Reasons = @($Entry.Reasons.ToArray())
                    ProposedTag = $(if ($Entry.Reasons.Count -gt 0 -and $Entry.Target) { "$Id/$($Entry.Target)" } else { $null })
                }
            }
        )
        $SourceAfter = Get-PreparationSourceState -Root $Root -Validated $Validated
        if ((ConvertTo-Json $SourceBefore -Depth 64 -Compress) -cne (ConvertTo-Json $SourceAfter -Depth 64 -Compress)) { throw 'Source changed during planning; repeat the preview.' }
        $OrderedImpact = [ordered]@{}
        foreach ($Id in @($Impact.Keys | Sort-Object)) { $OrderedImpact[$Id] = $Impact[$Id] }
        $Binding = [ordered]@{
            Source = $SourceAfter; Impact = $OrderedImpact; Bootstrap = @($BootstrapId | Sort-Object -Unique)
        }
        $Fingerprint = Get-PreparationHash ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Binding -Depth 64 -Compress)))
        $Plan = [pscustomobject]@{ Ready = ($Missing.Count -eq 0); Fingerprint = $Fingerprint; SourceCommit = $Head; Components = $Components; MissingDecisions = $Missing.ToArray(); Changes = $Changes.ToArray(); Applied = $false }
        if (-not $Apply) { return $Plan }
        if (-not $Plan.Ready) { throw 'Preparation is incomplete; review MissingDecisions in a fresh preview.' }
        if ($ReviewedFingerprint -cne $Fingerprint) { throw 'Stale or missing reviewed fingerprint; preview and review the current source and decisions before applying.' }
        $Stage = Join-Path $Scratch 'proposed'
        foreach ($Path in $SourceAfter.Inputs.Keys) {
            $Destination = Join-Path $Stage $Path
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination))
            [IO.File]::Copy((Join-Path $Root $Path), $Destination)
        }
        foreach ($Candidate in $Candidates) { [IO.File]::WriteAllBytes((Join-Path $Stage $Candidate.Path), $Candidate.Proposed) }
        [void](Invoke-SkillValidation -RepoRoot $Stage -PythonPath $PythonPath)
        foreach ($Candidate in $Candidates) {
            $Backup = Join-Path (Join-Path $Scratch 'originals') $Candidate.Path
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Backup))
            [IO.File]::WriteAllBytes($Backup, $Candidate.Original)
        }
        $Streams = @{}
        $Written = [Collections.Generic.List[object]]::new()
        try {
            foreach ($Candidate in $Candidates) {
                $FullPath = Assert-LibraryPath -Root $Root -Relative $Candidate.Path
                $Streams[$Candidate.Path] = [IO.File]::Open($FullPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
            }
            $Recheck = Invoke-SkillVersionPreparation -RepoRoot $Root -ImpactJson $ImpactJson -BootstrapId $BootstrapId -PythonPath $PythonPath
            if ($Recheck.Fingerprint -cne $Fingerprint) { throw 'Source changed during preparation; no writes applied.' }
            foreach ($Candidate in $Candidates) {
                [void](Assert-LibraryPath -Root $Root -Relative $Candidate.Path)
                if ((Get-PreparationHash (Read-PreparationBytes (Join-Path $Root $Candidate.Path))) -cne (Get-PreparationHash $Candidate.Original)) { throw 'Concurrent metadata change; refusing mutation.' }
                $Written.Add($Candidate)
                Set-PreparationBytes -Stream $Streams[$Candidate.Path] -Bytes $Candidate.Proposed
                $Candidate.Completed = $true
            }
            [void](Invoke-SkillValidation -RepoRoot $Root -PythonPath $PythonPath)
            foreach ($Candidate in $Candidates) {
                if ((Get-PreparationHash (Read-PreparationBytes (Join-Path $Root $Candidate.Path))) -cne (Get-PreparationHash $Candidate.Proposed)) { throw 'Concurrent metadata change after write; inspect recovery.' }
            }
            $ExpectedState = Get-PreparationSourceState -Root $Root -Validated $Validated
            foreach ($Candidate in $Candidates) {
                $SourceAfter.Inputs[$Candidate.Path] = Get-PreparationHash $Candidate.Proposed
                $ImplementationPath = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')), (Join-Path $Root $Candidate.Path))
                if ($SourceAfter.Implementation.Contains($ImplementationPath)) {
                    $SourceAfter.Implementation[$ImplementationPath] = Get-PreparationHash $Candidate.Proposed
                }
            }
            if ((ConvertTo-Json $ExpectedState -Depth 64 -Compress) -cne (ConvertTo-Json $SourceAfter -Depth 64 -Compress)) { throw 'Concurrent source change during apply; restore preparation and review again.' }
            $Plan.Applied = $true
        }
        catch {
            $Failure = $_
            foreach ($Candidate in $Written) {
                try {
                    $FullPath = Assert-LibraryPath -Root $Root -Relative $Candidate.Path
                    $Current = Read-PreparationBytes $FullPath
                    $CurrentHash = Get-PreparationHash $Current
                    if ($CurrentHash -ceq (Get-PreparationHash $Candidate.Original)) { continue }
                    $Owned = $CurrentHash -ceq (Get-PreparationHash $Candidate.Proposed)
                    if (-not $Owned -and -not $Candidate.Completed) {
                        $Prefix = 0
                        while ($Prefix -lt $Current.Length -and $Prefix -lt $Candidate.Proposed.Length -and $Current[$Prefix] -eq $Candidate.Proposed[$Prefix]) { $Prefix++ }
                        $Owned = $Current.Length -eq $Candidate.Original.Length -or $Prefix -eq $Current.Length
                        for ($Index = $Prefix; $Owned -and $Index -lt $Current.Length; $Index++) {
                            if ($Index -ge $Candidate.Original.Length -or $Current[$Index] -ne $Candidate.Original[$Index]) { $Owned = $false }
                        }
                    }
                    if (-not $Owned) { $RetainScratch = $true; continue }
                    $Stream = $Streams[$Candidate.Path]
                    $Stream.Position = 0
                    $Stream.Write($Candidate.Original, 0, $Candidate.Original.Length)
                    $Stream.SetLength($Candidate.Original.Length)
                    $Stream.Flush($true)
                    if ((Get-PreparationHash (Read-PreparationBytes $FullPath)) -cne (Get-PreparationHash $Candidate.Original)) { $RetainScratch = $true }
                }
                catch { $RetainScratch = $true }
            }
            if ($RetainScratch) {
                $Recovery = [InvalidOperationException]::new("Concurrent edits or failed recovery preserved; inspect original metadata backups in $Scratch before retrying.")
                $Recovery.Data['RecoveryDirectory'] = $Scratch
                throw $Recovery
            }
            throw $Failure
        }
        finally { foreach ($Stream in $Streams.Values) { $Stream.Dispose() } }
        return $Plan
    }
    finally { if (-not $RetainScratch -and (Test-Path -LiteralPath $Scratch)) { Remove-Item -LiteralPath $Scratch -Recurse -Force } }
}
#endregion

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-SkillVersionPreparation -RepoRoot $RepoRoot -ImpactJson $ImpactJson -BootstrapId $BootstrapId -PythonPath $PythonPath -Apply:$Apply -ReviewedFingerprint $ReviewedFingerprint | ConvertTo-Json -Depth 64
        exit 0
    }
    catch {
        Write-Error -Message "Version preparation failed: $($_.Exception.Message)" -ErrorAction Continue
        exit 1
    }
}
#endregion
