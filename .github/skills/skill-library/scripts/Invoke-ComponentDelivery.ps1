#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Calculate independently versioned skill delivery from explicit release decisions.
.DESCRIPTION
Reuse reviewed version preparation without editing source, creating tags or publishing packages.
BuildReady requires complete decisions and already prepared metadata with no remaining scalar edits.
.PARAMETER RepoRoot
Absolute repository root, defaulting to this script's containing repository.
.PARAMETER ImpactJson
JSON object mapping each affected released component to patch, minor or major.
.PARAMETER BootstrapId
Explicit acknowledgements for unpublished component versions.
.PARAMETER PythonPath
Existing Python interpreter with the pinned metadata prerequisites.
.PARAMETER Build
Build affected component artifacts only from clean committed prepared source.
.PARAMETER OutputDirectory
New absolute output directory outside source and Git administrative directories.
.PARAMETER LibraryCatalogPath
Existing exact release catalogs needed to bundle unchanged skills in a bootstrap.
.PARAMETER BaseUri
HTTPS or loopback catalog location; local packaging does not publish to this URI.
.EXAMPLE
./Invoke-ComponentDelivery.ps1 -BootstrapId example-skill -PythonPath /path/to/python
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'),
    [string]$ImpactJson = '{}',
    [string[]]$BootstrapId = @(),
    [string]$PythonPath = 'python3',
    [switch]$Build,
    [string]$OutputDirectory = '',
    [string[]]$LibraryCatalogPath = @(),
    [string]$BaseUri = 'https://example.com/skills/'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$DeliveryInputs = @{
    RepoRoot = $RepoRoot; ImpactJson = $ImpactJson; BootstrapId = $BootstrapId; PythonPath = $PythonPath
    Build = $Build; OutputDirectory = $OutputDirectory; LibraryCatalogPath = $LibraryCatalogPath; BaseUri = $BaseUri
}
. (Join-Path $PSScriptRoot 'Invoke-VersionPreparation.ps1') -RepoRoot $RepoRoot -ImpactJson $ImpactJson -BootstrapId $BootstrapId -PythonPath $PythonPath

function Invoke-SkillComponentDelivery {
    param(
        [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'), [string]$ImpactJson = '{}', [string[]]$BootstrapId = @(), [string]$PythonPath = 'python3',
        [switch]$Build, [string]$OutputDirectory = '', [string[]]$LibraryCatalogPath = @(),
        [string]$BaseUri = 'https://example.com/skills/'
    )
    $Preparation = Invoke-SkillVersionPreparation -RepoRoot $RepoRoot -ImpactJson $ImpactJson -BootstrapId $BootstrapId -PythonPath $PythonPath
    $Result = [pscustomobject]@{
        Contract = 'skill-component-delivery/1'
        SourceCommit = $Preparation.SourceCommit
        Fingerprint = $Preparation.Fingerprint
        Ready = $Preparation.Ready
        BuildReady = ($Preparation.Ready -and $Preparation.Changes.Count -eq 0)
        Preparation = $Preparation
        Artifacts = @()
    }
    if (-not $Build) { return $Result }
    if (-not $Result.BuildReady) { throw 'Commit the complete reviewed version preparation before building.' }
    $Root = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('/')
    if (Invoke-PreparationGit -Root $Root -Arguments @('status', '--porcelain', '--untracked-files=all')) { throw 'Build requires clean committed source.' }
    if (-not $IsLinux -or -not [IO.Path]::IsPathFullyQualified($OutputDirectory) -or $OutputDirectory.Contains('\') -or
        @($OutputDirectory.Substring(1).Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) { throw 'Use a new unambiguous absolute Linux output directory.' }
    $Destination = $OutputDirectory.TrimEnd('/')
    $Parent = Get-Item -LiteralPath ([IO.Path]::GetDirectoryName($Destination)) -Force
    if (-not $Parent.PSIsContainer -or (Test-Path -LiteralPath $Destination)) { throw 'Output must be absent beneath an existing trusted directory.' }
    while ($null -ne $Parent) {
        if ($Parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked output ancestry is not supported.' }
        $Parent = $Parent.Parent
    }
    $Boundaries = @($Root)
    foreach ($Argument in @('--absolute-git-dir', '--git-common-dir')) {
        $Boundary = Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', '--path-format=absolute', $Argument)
        $Boundaries += $Boundary.TrimEnd('/')
    }
    foreach ($Boundary in $Boundaries) {
        if ($Destination -ceq $Boundary -or $Destination.StartsWith("$Boundary/", [StringComparison]::Ordinal) -or $Boundary.StartsWith("$Destination/", [StringComparison]::Ordinal)) { throw 'Output overlaps source or Git administrative storage.' }
    }
    $Candidates = @($Preparation.Components | Where-Object { $null -ne $_.ProposedTag })
    if ($Candidates.Count -eq 0) { throw 'There are no affected components to package.' }
    . (Join-Path $PSScriptRoot 'Invoke-Archive.ps1') -RepoRoot $Root -OutputDirectory $Destination -PythonPath $PythonPath
    . (Join-Path $PSScriptRoot 'Invoke-Extension.ps1') -OutputDirectory $Destination -BaseUri $BaseUri -LibraryCatalogPath $LibraryCatalogPath
    if (Test-Path -LiteralPath $Destination) { throw 'Output appeared before reservation.' }
    [void](New-Item -ItemType Directory -Path $Destination -ErrorAction Stop)
    try {
        $NativeRoot = Join-Path $Destination 'native'
        $ComponentRoot = Join-Path $Destination 'components'
        [void][IO.Directory]::CreateDirectory($NativeRoot)
        [void][IO.Directory]::CreateDirectory($ComponentRoot)
        $Catalogs = [Collections.Generic.List[string]]::new()
        foreach ($Component in @($Candidates | Sort-Object @{ Expression = { $_.Id -ceq 'skill-library' } }, Id)) {
            if ((Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', 'HEAD')) -cne $Preparation.SourceCommit -or
                (Invoke-PreparationGit -Root $Root -Arguments @('status', '--porcelain', '--untracked-files=all'))) { throw 'Committed source changed during delivery.' }
            $Folder = [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($Component.Path))
            $Archive = Invoke-SkillArchive -RepoRoot $Root -SourceRevision $Preparation.SourceCommit -SkillName $Folder -OutputDirectory (Join-Path $NativeRoot $Component.Id) -PythonPath $PythonPath
            $ComponentDirectory = Join-Path $ComponentRoot $Component.Id
            [void][IO.Directory]::CreateDirectory($ComponentDirectory)
            $Arguments = @{
                ArchivePath = $Archive.ArchivePath; ArchiveSha256 = $Archive.ArchiveSha256
                OutputDirectory = (Join-Path $ComponentDirectory $Component.Target); BaseUri = $BaseUri
            }
            if ($Component.Id -ceq 'skill-library') { $Arguments.LibraryCatalogPath = @($Catalogs.ToArray()) + @($LibraryCatalogPath) }
            $Package = Invoke-SkillExtension @Arguments
            if ($Package.RootVersion -cne $Component.Target) { throw 'Built version does not match the reviewed preparation.' }
            $Result.Artifacts += $Package
            $Catalogs.Add($Package.CatalogPath)
        }
        if ((Invoke-PreparationGit -Root $Root -Arguments @('rev-parse', 'HEAD')) -cne $Preparation.SourceCommit -or
            (Invoke-PreparationGit -Root $Root -Arguments @('status', '--porcelain', '--untracked-files=all'))) { throw 'Committed source changed during delivery.' }
        $Evidence = Join-Path $Destination 'delivery.json'
        $Stream = [IO.File]::Open($Evidence, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $Stream.Write([Text.Encoding]::UTF8.GetBytes(($Result | ConvertTo-Json -Depth 100) + "`n")); $Stream.Flush($true) }
        finally { $Stream.Dispose() }
        return $Result
    }
    catch { throw "Delivery build failed; preserve partial output at $Destination for inspection. No delivery success is reported." }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Result = Invoke-SkillComponentDelivery @DeliveryInputs
        $Result | ConvertTo-Json -Depth 100
        if (-not $Result.Ready) { exit 2 }
        exit 0
    }
    catch {
        [Console]::Error.WriteLine('Component delivery planning failed; inspect explicit version decisions and trusted local history.')
        exit 1
    }
}
