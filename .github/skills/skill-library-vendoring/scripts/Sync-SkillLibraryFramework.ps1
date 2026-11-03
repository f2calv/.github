#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Copies the skill-library framework from a release tag of a source clone into a target repository.
.DESCRIPTION
Reads framework.yaml at the tag, then copies its managed files into the target and creates its seeded
files once. A managed file is overwritten or deleted only while it still matches the SHA-256 recorded
in the target's .github/skill-library.framework.lock.json, so local edits are kept and reported. The
lock records the source repository, tag, commit and every file written. Nothing is read from the
source working tree and nothing is written to the source. ADR 0004 records the design.
.PARAMETER Source
Clone of the repository that publishes the framework; fetch its tags first.
.PARAMETER Target
Root of the repository that adopts the framework.
.PARAMETER Ref
skill-library/X.Y.Z tag to copy from; defaults to the highest skill-library tag in Source.
.EXAMPLE
./.github/skills/skill-library-vendoring/scripts/Sync-SkillLibraryFramework.ps1 -Source . -Target ../adopter -WhatIf
.NOTES
Needs Git and Mike Farah yq v4. Emits one object per framework path with Path, Action and Detail.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Target,
    [string]$Ref = ''
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

$ManifestPath = '.github/skills/skill-library-vendoring/framework.yaml'
$LockPath = '.github/skill-library.framework.lock.json'
$TagPrefix = 'skill-library/'

function Invoke-Git([string]$Repo, [string[]]$Arguments) {
    $Output = & git -C $Repo @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in ${Repo}: $($Output -join "`n")" }
    return @($Output | ForEach-Object { "$_" })
}

function Get-RepositoryRoot([string]$Path, [string]$Role) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Role '$Path' is not a directory." }
    $Root = @(& git -C $Path rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $Root) { throw "$Role '$Path' is not a Git repository." }
    return [IO.Path]::GetFullPath($Root[0])
}

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Assert-RelativePath([string]$Path) {
    if (-not $Path -or $Path.StartsWith('/') -or $Path -match '\\|(^|/)\.\.(/|$)|^[A-Za-z]:') { throw "framework.yaml path '$Path' must be repository-relative." }
}

function Remove-EmptyParent([string]$Root, [string]$Path) {
    $Dir = [IO.Path]::GetDirectoryName($Path)
    while ($Dir -and $Dir.Length -gt $Root.Length -and -not (Get-ChildItem -LiteralPath $Dir -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $Dir
        $Dir = [IO.Path]::GetDirectoryName($Dir)
    }
}

function New-Result([string]$Path, [string]$Action, [string]$Detail = '') { [pscustomobject]@{ Path = $Path; Action = $Action; Detail = $Detail } }

$SourceRoot = Get-RepositoryRoot $Source 'Source'
$TargetRoot = Get-RepositoryRoot $Target 'Target'
if ($SourceRoot -eq $TargetRoot) { throw 'Source and Target must be different repositories.' }

if (-not $Ref) {
    $Ref = Invoke-Git $SourceRoot @('tag', '--list', "$TagPrefix*") | Where-Object { $_.Substring($TagPrefix.Length) -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Substring($TagPrefix.Length) } -Descending | Select-Object -First 1
    if (-not $Ref) { throw "Source has no $TagPrefix<version> tags; run git fetch --tags." }
}
if (-not $Ref.StartsWith($TagPrefix, [StringComparison]::Ordinal)) { throw "Ref must be a $TagPrefix<version> tag, got '$Ref'." }
$Commit = @(& git -C $SourceRoot rev-parse --verify --quiet "$Ref^{commit}") | Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or -not $Commit) { throw "Source has no tag '$Ref'; run git fetch --tags." }

$ManifestText = @(& git -C $SourceRoot show "${Commit}:$ManifestPath" 2>$null)
if ($LASTEXITCODE -ne 0) { throw "$Ref has no $ManifestPath; use a later $TagPrefix tag." }
$ManifestJson = ($ManifestText -join "`n") | & yq -p=yaml -o=json '.'
if ($LASTEXITCODE -ne 0) { throw "$Ref has an invalid $ManifestPath." }
$Manifest = ($ManifestJson -join "`n") | ConvertFrom-Json -AsHashtable
$Managed = @($Manifest['managed'] ?? @())
$Seeded = @($Manifest['seeded'] ?? @())
foreach ($Entry in $Managed) { Assert-RelativePath $Entry.path; foreach ($Excluded in @($Entry['exclude'] ?? @())) { Assert-RelativePath $Excluded } }
foreach ($Entry in $Seeded) { Assert-RelativePath $Entry.path; Assert-RelativePath $Entry.from }

# git archive reads committed blobs only; autocrlf off keeps hashes identical on every platform.
$Stage = Join-Path ([IO.Path]::GetTempPath()) "skill-library-sync-$([guid]::NewGuid())"
[void][IO.Directory]::CreateDirectory($Stage)
try {
    $Zip = Join-Path $Stage 'framework.zip'
    $Paths = @($Managed | ForEach-Object { $_.path.TrimEnd('/') }) + @($Seeded | ForEach-Object { $_.from }) | Sort-Object -Unique
    Invoke-Git $SourceRoot (@('-c', 'core.autocrlf=false', 'archive', '--format=zip', '-o', $Zip, $Commit, '--') + $Paths) | Out-Null
    $Tree = Join-Path $Stage 'tree'
    Expand-Archive -LiteralPath $Zip -DestinationPath $Tree -WhatIf:$false

    $Wanted = [ordered]@{}
    foreach ($Entry in $Managed) {
        $Excluded = @($Entry['exclude'] ?? @())
        $Base = Join-Path $Tree $Entry.path.TrimEnd('/')
        $Files = if (Test-Path -LiteralPath $Base -PathType Container) { @(Get-ChildItem -LiteralPath $Base -File -Recurse -Force) } else { @(Get-Item -LiteralPath $Base) }
        foreach ($File in $Files) {
            $Rel = [IO.Path]::GetRelativePath($Tree, $File.FullName).Replace('\', '/')
            if ($Rel -cnotin $Excluded) { $Wanted[$Rel] = $File.FullName }
        }
    }

    $LockFile = Join-Path $TargetRoot $LockPath
    $Records = @{}
    if (Test-Path -LiteralPath $LockFile) { $Records = (Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json -AsHashtable)['files'] ?? @{} }
    $Next = @{}
    $Results = [Collections.Generic.List[object]]::new()

    $Ordinal = [StringComparer]::Ordinal
    $WantedKeys = [string[]]@($Wanted.Keys)
    [Array]::Sort($WantedKeys, $Ordinal)
    foreach ($Rel in $WantedKeys) {
        $Path = Join-Path $TargetRoot $Rel
        $New = Get-Sha256 $Wanted[$Rel]
        $Current = if (Test-Path -LiteralPath $Path -PathType Leaf) { Get-Sha256 $Path } else { $null }
        $Record = $Records[$Rel]
        $Write = $false
        if (-not $Current) { $Write = $true; $Results.Add((New-Result $Rel 'Added')) }
        elseif ($Current -ceq $New) { $Next[$Rel] = [ordered]@{ kind = 'managed'; sha256 = $New }; $Results.Add((New-Result $Rel 'Unchanged')); continue }
        elseif ($Record -and $Current -ceq $Record.sha256) { $Write = $true; $Results.Add((New-Result $Rel 'Updated')) }
        elseif (-not $Record) { $Results.Add((New-Result $Rel 'Kept' 'exists and was not written by a sync; compare it with the framework copy')); continue }
        else { $Next[$Rel] = $Record; $Results.Add((New-Result $Rel 'Kept' 'modified since the last sync; the framework change was not applied')); continue }
        if ($Write -and $PSCmdlet.ShouldProcess($Rel, 'Write framework file')) {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
            Copy-Item -LiteralPath $Wanted[$Rel] -Destination $Path -Force
        }
        $Next[$Rel] = [ordered]@{ kind = 'managed'; sha256 = $New }
    }

    $RecordKeys = [string[]]@($Records.Keys)
    [Array]::Sort($RecordKeys, $Ordinal)
    foreach ($Rel in $RecordKeys) {
        $Record = $Records[$Rel]
        if ($Record.kind -cne 'managed' -or $Wanted.Contains($Rel)) { continue }
        $Path = Join-Path $TargetRoot $Rel
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { continue }
        if ((Get-Sha256 $Path) -cne $Record.sha256) { $Results.Add((New-Result $Rel 'Kept' 'no longer part of the framework but modified; review it before deleting it')); continue }
        if ($PSCmdlet.ShouldProcess($Rel, 'Delete retired framework file')) {
            Remove-Item -LiteralPath $Path
            Remove-EmptyParent $TargetRoot $Path
        }
        $Results.Add((New-Result $Rel 'Removed'))
    }

    foreach ($Entry in $Seeded) {
        $Rel = $Entry.path
        $Path = Join-Path $TargetRoot $Rel
        $Record = $Records[$Rel]
        if ($Record -and $Record.kind -ceq 'seeded') { $Next[$Rel] = $Record; continue }
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $Results.Add((New-Result $Rel 'Skipped' "exists; merge $($Entry.from) from $Ref by hand if this repository needs it"))
            continue
        }
        $From = Join-Path $Tree $Entry.from
        if ($PSCmdlet.ShouldProcess($Rel, 'Seed framework file')) {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
            Copy-Item -LiteralPath $From -Destination $Path
        }
        $Next[$Rel] = [ordered]@{ kind = 'seeded'; sha256 = (Get-Sha256 $From) }
        $Results.Add((New-Result $Rel 'Seeded'))
    }

    if ($PSCmdlet.ShouldProcess($LockPath, 'Write sync lock')) {
        $Origin = @(& git -C $SourceRoot remote get-url origin 2>$null)
        # Strip any user information so a token in the remote URL never reaches the target repository.
        $Repository = if ($LASTEXITCODE -eq 0 -and $Origin) { $Origin[0] -replace '://[^/@]+@', '://' } else { '' }
        $Files = [ordered]@{}
        $NextKeys = [string[]]@($Next.Keys)
        [Array]::Sort($NextKeys, $Ordinal)
        foreach ($Rel in $NextKeys) { $Files[$Rel] = $Next[$Rel] }
        $Lock = [ordered]@{ schema_version = '1.0'; source = [ordered]@{ repository = $Repository; ref = $Ref; commit = $Commit }; files = $Files }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($LockFile))
        [IO.File]::WriteAllText($LockFile, ($Lock | ConvertTo-Json -Depth 5) + "`n")
    }
    $Results
}
finally { Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false }
