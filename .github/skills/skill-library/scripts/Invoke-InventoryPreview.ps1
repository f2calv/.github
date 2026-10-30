#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Preview committed skill payload membership and declaration attribution without writes.
.DESCRIPTION
Use the invoked trusted validator bundle against one inert local commit. Select native roots and
explicit optional edges using the existing validation contract. Emit JSON only after cleanup.
.PARAMETER RepoRoot
Actual local repository root, defaulting to the repository containing this script.
.PARAMETER SourceRevision
Unambiguous locally available revision resolving to one commit. Defaults to HEAD.
.PARAMETER SkillName
Native root folder names. Empty selects every opted-in component.
.PARAMETER OptionalSelection
Explicit reachable component-id/selectionKey identifiers. Duplicates are invalid.
.PARAMETER PythonPath
Existing Python 3.11+ with PyYAML 6.0.3. Defaults to python3; no provisioning occurs.
.EXAMPLE
./Invoke-InventoryPreview.ps1 -SkillName example-skill -PythonPath /path/to/python
.NOTES
No archive, install, export, apply, version, tag or publication operations. Local edits are excluded.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'),
    [string]$SourceRevision = 'HEAD',
    [string[]]$SkillName = @(),
    [string[]]$OptionalSelection = @(),
    [string]$PythonPath = 'python3'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'Git-Process.ps1')

#region Functions
function New-InventoryScratch {
    param([string]$Root)
    $TemporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($TemporaryRoot.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or
        $TemporaryRoot.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Temporary storage must be outside the source repository.'
    }
    return [IO.Directory]::CreateTempSubdirectory('skill-inventory-').FullName
}

function Remove-InventoryScratch {
    param([string]$Path)
    if ([IO.Directory]::Exists($Path)) { [IO.Directory]::Delete($Path, $true) }
}

function Get-InventoryOrder {
    param([string[]]$Values)
    $Ordered = [string[]]@($Values)
    [Array]::Sort($Ordered, [StringComparer]::Ordinal)
    return ,$Ordered
}

function Assert-InventorySourcePath {
    param([string]$Path)
    if ($Path -notmatch '^(?!/)(?!.*(?:^|/)\.\.?(?:/|$))(?!.*[\\:\x00-\x1f])[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$') {
        throw 'Unsafe committed path.'
    }
    foreach ($Segment in $Path.Split('/')) {
        if ($Segment -match '^(?i:\.env(?:\..*)?|.*\.(?:pem|key|pfx|p12)|secrets?(?:\..*)?|\.git|__pycache__|node_modules)$') {
            throw 'Unsafe committed input name.'
        }
    }
}

function Invoke-InventoryGitRead {
    param([object]$Context, [string[]]$Arguments, [switch]$Bytes)
    $Result = Invoke-LibraryGit -Root $Context.Root -Arguments $Arguments -Environment $Context.Environment
    if ($Result.ExitCode -ne 0 -or $Result.Error.Length -gt 0) { throw [IO.IOException]::new('Local Git inspection failed.') }
    if ($Bytes) { return ,$Result.Bytes }
    return [Text.UTF8Encoding]::new($false, $true).GetString($Result.Bytes).TrimEnd("`n", "`r")
}

function Get-InventoryChildren {
    param([object]$Context, [string]$Directory = '')
    if ($Context.Directories.ContainsKey($Directory)) { return ,$Context.Directories[$Directory] }
    $Object = $Context.Commit
    if ($Directory) {
        $Entry = Get-InventorySourceEntry -Context $Context -Path $Directory
        if ($null -eq $Entry) { return ,@() }
        if ($Entry.Mode -ne '040000' -or $Entry.Type -ne 'tree') { throw 'Source ancestor is not a regular tree.' }
        $Object = $Entry.Object
    }
    $Listing = Invoke-InventoryGitRead -Context $Context -Arguments @('ls-tree', '-z', $Object)
    $Children = [Collections.Generic.List[string]]::new()
    foreach ($Line in $Listing.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
        $Fields = $Line.Split("`t", 2)
        $Header = $Fields[0].Split(' ')
        if ($Fields.Count -ne 2 -or $Header.Count -ne 3) { throw 'Malformed source tree.' }
        $Path = if ($Directory) { "$Directory/$($Fields[1])" } else { $Fields[1] }
        $Context.Entries[$Path] = [pscustomobject]@{ Mode = $Header[0]; Type = $Header[1]; Object = $Header[2] }
        $Children.Add($Path)
    }
    $Context.Directories[$Directory] = $Children.ToArray()
    return ,$Children.ToArray()
}

function Get-InventorySourceEntry {
    param([object]$Context, [string]$Path)
    Assert-InventorySourcePath $Path
    $Parent = ''
    foreach ($Segment in $Path.Split('/')) {
        [void](Get-InventoryChildren -Context $Context -Directory $Parent)
        $Current = if ($Parent) { "$Parent/$Segment" } else { $Segment }
        if (-not $Context.Entries.ContainsKey($Current)) { return $null }
        if ($Current -cne $Path -and $Context.Entries[$Current].Mode -ne '040000') { throw 'Unsafe source ancestor.' }
        $Parent = $Current
    }
    return $Context.Entries[$Path]
}

function Add-InventorySourceFile {
    param([object]$Context, [string]$Path)
    $Entry = Get-InventorySourceEntry -Context $Context -Path $Path
    if ($null -eq $Entry) { throw 'Missing committed input.' }
    if ($Entry.Type -ne 'blob' -or $Entry.Mode -notin @('100644', '100755')) { throw 'Unsupported committed input.' }
    [void]$Context.StagePaths.Add($Path)
}

function Add-InventorySourceTree {
    param([object]$Context, [string]$Directory)
    foreach ($Path in (Get-InventoryChildren -Context $Context -Directory $Directory)) {
        Assert-InventorySourcePath $Path
        if ($Context.Entries[$Path].Mode -eq '040000') { Add-InventorySourceTree -Context $Context -Directory $Path }
        else { Add-InventorySourceFile -Context $Context -Path $Path }
    }
}

function Read-InventoryDeclaration {
    param([object]$Context, [string]$Path, [string]$Schema, [string]$PythonPath)
    Add-InventorySourceFile -Context $Context -Path $Path
    $Raw = Join-Path $Context.Scratch 'declaration.yaml'
    $Bytes = Invoke-InventoryGitRead -Context $Context -Arguments @('cat-file', 'blob', $Context.Entries[$Path].Object) -Bytes
    [IO.File]::WriteAllBytes($Raw, $Bytes)
    $Record = Read-SkillYaml -Path $Raw -PythonPath $PythonPath
    if (-not (Test-Json -Json (ConvertTo-Json -InputObject $Record -Depth 64 -Compress) -SchemaFile $Schema -ErrorAction SilentlyContinue)) {
        throw 'Authoritative declaration schema rejected source input.'
    }
    return $Record
}

function Copy-InventoryRules {
    param([string]$Destination)
    $SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $Paths = @('scripts/Invoke-Validation.ps1', 'scripts/Read-Metadata.py', 'scripts/Git-Process.ps1', 'skill-metadata.schema.json', 'repository-defaults.schema.json')
    $Captured = @{}
    foreach ($Path in $Paths) {
        $Source = Join-Path $SourceRoot $Path
        $Ancestor = Get-Item -LiteralPath $Source -Force
        while ($null -ne $Ancestor) {
            if ($Ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Trusted rules cannot use links.' }
            $Ancestor = if ($Ancestor -is [IO.FileInfo]) { $Ancestor.Directory } else { $Ancestor.Parent }
        }
        $Captured[$Path] = [IO.File]::ReadAllBytes($Source)
    }
    foreach ($Path in $Paths) {
        if ([Convert]::ToBase64String($Captured[$Path]) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $SourceRoot $Path)))) {
            throw 'Trusted rules changed during capture.'
        }
        $Target = Join-Path $Destination $Path
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
        [IO.File]::WriteAllBytes($Target, $Captured[$Path])
    }
}

function Set-InventoryEligibility {
    param([object]$Context)
    $Parents = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Path in @($Context.StagePaths)) {
        [void]$Parents.Add('')
        $Parent = $Path
        while ($Parent.Contains('/')) { $Parent = $Parent.Substring(0, $Parent.LastIndexOf('/')); [void]$Parents.Add($Parent) }
    }
    foreach ($Parent in $Parents) {
        $Ignore = if ($Parent) { "$Parent/.gitignore" } else { '.gitignore' }
        if ($null -ne (Get-InventorySourceEntry -Context $Context -Path $Ignore)) { Add-InventorySourceFile -Context $Context -Path $Ignore }
    }
    $Folded = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Path in (Get-InventoryOrder @($Context.StagePaths))) {
        $Current = ''
        foreach ($Segment in $Path.Split('/')) {
            $Current = if ($Current) { "$Current/$Segment" } else { $Segment }
            if ($Folded.ContainsKey($Current) -and $Folded[$Current] -cne $Current) { throw 'Case-insensitive source collision.' }
            $Folded[$Current] = $Current
        }
    }
    foreach ($Path in (Get-InventoryOrder @($Context.StagePaths))) {
        $Target = Join-Path $Context.Data $Path
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
        [IO.File]::WriteAllBytes($Target, (Invoke-InventoryGitRead -Context $Context -Arguments @('cat-file', 'blob', $Context.Entries[$Path].Object) -Bytes))
    }
}

function Get-InventoryEligiblePaths {
    param([object]$Context)
    $Template = Join-Path $Context.Scratch 'empty-template'
    $Matcher = Join-Path $Context.Scratch 'matcher.git'
    [void][IO.Directory]::CreateDirectory($Template)
    [void](Invoke-InventoryGitRead -Context $Context -Arguments @('init', '--bare', '-q', "--template=$Template", $Matcher))
    $Paths = Get-InventoryOrder @($Context.StagePaths)
    $InputBytes = [Text.Encoding]::UTF8.GetBytes(($Paths -join [char]0) + [char]0)
    $Result = Invoke-LibraryGit -Root $Context.Data -Arguments @(
        "--git-dir=$Matcher", "--work-tree=$($Context.Data)", '-c', 'core.bare=false',
        '-c', 'core.ignoreCase=false', '-c', "core.excludesFile=$($Context.EmptyFile)",
        'check-ignore', '--no-index', '--stdin', '-z'
    ) -InputBytes $InputBytes -Environment $Context.Environment
    if ($Result.ExitCode -notin @(0, 1) -or $Result.Error.Length -gt 0) { throw 'Snapshot ignore matching failed.' }
    $Ignored = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Path in [Text.UTF8Encoding]::new($false, $true).GetString($Result.Bytes).Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
        [void]$Ignored.Add($Path)
    }
    foreach ($Path in $Paths) { if (-not $Ignored.Contains($Path)) { [void]$Context.Eligible.Add($Path) } }
}

function Invoke-InventoryInspection {
    param(
        [string]$RepoRoot, [string]$SourceRevision = 'HEAD', [string[]]$SkillName = @(),
        [string[]]$OptionalSelection = @(), [string]$PythonPath = 'python3', [scriptblock]$Inspect
    )
    $Scratch = $null
    $Category = 'Prerequisite'
    $Guidance = @{
        Prerequisite = 'Supply installed Git, PowerShell 7.4+ and Python 3.11+ with PyYAML 6.0.3.'
        Source = 'Supply an unambiguous locally available commit and the actual repository root.'
        Validation = 'Correct authoritative declarations, native content or selections in the chosen commit.'
        Eligibility = 'Correct committed ignore rules or mandatory file declarations.'
        Inspection = 'Restore readable safe local source and trusted tooling; no working-file fallback is used.'
    }
    try {
        [void](Get-Command git -CommandType Application -TotalCount 1)
        $Python = (Get-Command $PythonPath -CommandType Application -TotalCount 1).Source
        $Probe = Invoke-LibraryProcess -Executable $Python -Arguments @('-I', '-B', '-c', 'import sys, yaml; sys.exit(0 if sys.version_info >= (3, 11) and yaml.__version__ == "6.0.3" else 1)')
        if ($Probe.ExitCode -ne 0) { throw 'Unsupported installed Python prerequisites.' }
        $Category = 'Source'
        $Root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $Ancestor = Get-Item -LiteralPath $Root -Force
        while ($null -ne $Ancestor) {
            if ($Ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unsafe repository ancestor.' }
            $Ancestor = $Ancestor.Parent
        }
        $Request = @{ Root = $Root; Skills = $SkillName; Options = $OptionalSelection; Revision = $SourceRevision }
        $Category = 'Inspection'
        $Scratch = New-InventoryScratch -Root $Root
        $Rules = Join-Path $Scratch 'rules'
        Copy-InventoryRules -Destination $Rules
        $EmptyFile = Join-Path $Scratch 'empty-config'
        [IO.File]::WriteAllText($EmptyFile, '')
        $Context = [pscustomobject]@{
            Root = $Root; Scratch = $Scratch; Data = (Join-Path $Scratch 'data'); Rules = $Rules; EmptyFile = $EmptyFile
            Commit = ''; Entries = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
            Directories = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
            StagePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            Eligible = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            Raw = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
            RawDefaults = $null; Validated = $null; Native = @{}; Roots = @(); OptionalSelections = @()
            Environment = @{ GIT_CONFIG_GLOBAL = $EmptyFile; GIT_CONFIG_SYSTEM = $EmptyFile; GIT_CONFIG_NOSYSTEM = '1' }
        }
        [void][IO.Directory]::CreateDirectory($Context.Data)
        . (Join-Path $Rules 'scripts/Git-Process.ps1')
        $Category = 'Source'
        $ActualRoot = Invoke-InventoryGitRead $Context @('rev-parse', '--show-toplevel')
        if (-not $ActualRoot.Equals($Root, [StringComparison]::Ordinal)) { throw 'Use the actual repository root.' }
        $Context.Commit = Invoke-InventoryGitRead $Context @('rev-parse', '--verify', '--end-of-options', "$($Request.Revision)^{commit}")
        if ($Context.Commit -cnotmatch '^[0-9a-f]+$') { throw 'Invalid commit identity.' }
        $Category = 'Inspection'
        . (Join-Path $Rules 'scripts/Invoke-Validation.ps1') -RepoRoot $Context.Data -SkillName $Request.Skills -OptionalSelection $Request.Options -PythonPath $Python
        $DefaultsPath = '.config/skill-library.yaml'
        $Category = 'Validation'
        $Context.RawDefaults = Read-InventoryDeclaration $Context $DefaultsPath (Join-Path $Rules 'repository-defaults.schema.json') $Python
        if ($Context.RawDefaults.ContainsKey('notices')) {
            foreach ($Path in $Context.RawDefaults.notices) { Add-InventorySourceFile $Context $Path }
        }
        if ($null -ne (Get-InventorySourceEntry -Context $Context -Path '.skillsignore')) {
            Add-InventorySourceFile -Context $Context -Path '.skillsignore'
            [IO.File]::WriteAllBytes((Join-Path $Context.Data '.skillsignore'),
                (Invoke-InventoryGitRead -Context $Context -Arguments @('cat-file', 'blob', $Context.Entries['.skillsignore'].Object) -Bytes))
        }
        $Exclusions = @(Read-SkillExclusions -Root $Context.Data)
        $Category = 'Inspection'
        foreach ($Folder in (Get-InventoryChildren $Context '.github/skills')) {
            if ($Context.Entries[$Folder].Mode -ne '040000') { continue }
            if (Test-SkillExcluded -Name ($Folder.Split('/')[-1]) -Patterns $Exclusions) { continue }
            $Sidecar = "$Folder/skill.metadata.yaml"
            if ($null -eq (Get-InventorySourceEntry $Context $Sidecar)) { continue }
            Add-InventorySourceTree $Context $Folder
            $Category = 'Validation'
            $Record = Read-InventoryDeclaration $Context $Sidecar (Join-Path $Rules 'skill-metadata.schema.json') $Python
            if ($Context.Raw.ContainsKey($Record.id)) { throw 'Duplicate component identity.' }
            $Context.Raw[$Record.id] = $Record
            $Context.Native[$Record.id] = $Folder
            if ($Record.ContainsKey('notices')) { foreach ($Path in $Record.notices) { Add-InventorySourceFile $Context $Path } }
            if ($Record.ContainsKey('externalFiles')) { foreach ($External in $Record.externalFiles) { Add-InventorySourceFile $Context $External.path } }
            $Category = 'Inspection'
        }
        Set-InventoryEligibility $Context
        $Category = 'Validation'
        $Context.Validated = Invoke-SkillValidation -RepoRoot $Context.Data -SkillName $Request.Skills -OptionalSelection $Request.Options -PythonPath $Python -IncludeCatalog
        $RootSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        if ($Request.Skills.Count -eq 0) { foreach ($Name in $Context.Validated.Folders.Keys) { [void]$RootSet.Add($Name) } }
        else {
            foreach ($Name in $Request.Skills) {
                $Id = $Context.Validated.Folders[$Name]
                [void]$RootSet.Add($Context.Native[$Id].Substring('.github/skills/'.Length))
            }
        }
        $Context.Roots = Get-InventoryOrder @($RootSet)
        $Context.OptionalSelections = Get-InventoryOrder $Request.Options
        $Category = 'Inspection'
        Get-InventoryEligiblePaths $Context
        $Category = 'Eligibility'
        foreach ($Id in $Context.Validated.SelectedIds) {
            $Folder = $Context.Native[$Id]
            $Mandatory = @("$Folder/SKILL.md", "$Folder/skill.metadata.yaml") + @($Context.Validated.Catalog[$Id].notices) + @($Context.Validated.Catalog[$Id].externalFiles | ForEach-Object { $_.path })
            foreach ($Path in $Mandatory) { if (-not $Context.Eligible.Contains($Path)) { throw 'Ignored mandatory input.' } }
        }
        $Category = 'Inspection'
        $Result = & $Inspect $Context
    }
    catch {
        if ($_.Exception -is [IO.IOException] -and $Category -ne 'Source') { $Category = 'Inspection' }
        throw "${Category}: $($Guidance[$Category])"
    }
    finally {
        if ($Scratch) {
            try { Remove-InventoryScratch $Scratch }
            catch { throw "Cleanup: Temporary inspection data retained at $Scratch; deliberate local cleanup is required. No success is reported." }
        }
    }
    return $Result
}

function Get-InventoryReasonOrder {
    param([object[]]$Reasons, [string[]]$Fields)
    $Ordered = [Collections.Generic.List[object]]::new()
    foreach ($Reason in $Reasons) { $Ordered.Add($Reason) }
    $Compare = {
        param($Left, $Right)
        foreach ($Field in $Fields) {
            $LeftProperty = $Left.PSObject.Properties[$Field]
            $RightProperty = $Right.PSObject.Properties[$Field]
            $LeftValue = if ($null -eq $LeftProperty) { '' } else { [string]$LeftProperty.Value }
            $RightValue = if ($null -eq $RightProperty) { '' } else { [string]$RightProperty.Value }
            $Comparison = [StringComparer]::Ordinal.Compare($LeftValue, $RightValue)
            if ($Comparison -ne 0) { return $Comparison }
        }
        return 0
    }.GetNewClosure()
    $Ordered.Sort([Comparison[object]]$Compare)
    return ,$Ordered.ToArray()
}

function Add-InventoryFileReason {
    param([object]$Context, [object]$Files, [string]$Path, [object]$Reason)
    if (-not $Files.ContainsKey($Path)) {
        $Files[$Path] = [pscustomobject]@{
            Path = $Path; SourceCommit = $Context.Commit; Mode = $Context.Entries[$Path].Mode
            Owners = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            Reasons = [Collections.Generic.List[object]]::new()
        }
    }
    [void]$Files[$Path].Owners.Add($Reason.ComponentId)
    $Files[$Path].Reasons.Add($Reason)
}

function New-InventoryResult {
    param([object]$Context)
    $Selected = $Context.Validated.SelectedIds
    $RootSets = @{}
    $ComponentReasons = @{}
    foreach ($Id in $Selected) {
        $RootSets[$Id] = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $ComponentReasons[$Id] = [Collections.Generic.List[object]]::new()
    }
    foreach ($Name in $Context.Roots) {
        $Id = $Context.Validated.Folders[$Name]
        [void]$RootSets[$Id].Add($Id)
        $ComponentReasons[$Id].Add([pscustomobject]@{
            Kind = 'root'; ToId = $Id; NativeFolder = $Context.Native[$Id]
            SourcePath = $Context.Native[$Id]; Field = 'selected-root'
        })
    }
    $Edges = [Collections.Generic.List[object]]::new()
    foreach ($Id in $Selected) {
        $Record = $Context.Validated.Catalog[$Id]
        for ($Index = 0; $Index -lt $Record.required.Count; $Index++) {
            $Edge = [pscustomobject]@{
                FromId = $Id; ToId = $Record.required[$Index].id; Kind = 'required'
                SourcePath = "$($Context.Native[$Id])/skill.metadata.yaml"; Field = "required[$Index]"
            }
            $Edges.Add($Edge)
            $ComponentReasons[$Edge.ToId].Add($Edge)
        }
        for ($Index = 0; $Index -lt $Record.optional.Count; $Index++) {
            $Declaration = $Record.optional[$Index]
            if ("$Id/$($Declaration.selectionKey)" -notin $Context.OptionalSelections) { continue }
            $Edge = [pscustomobject]@{
                FromId = $Id; ToId = $Declaration.id; Kind = 'optional'; SelectionKey = $Declaration.selectionKey
                SourcePath = "$($Context.Native[$Id])/skill.metadata.yaml"; Field = "optional[$Index]"
            }
            $Edges.Add($Edge)
            $ComponentReasons[$Edge.ToId].Add($Edge)
        }
    }
    for ($Index = $Selected.Count - 1; $Index -ge 0; $Index--) {
        $Id = $Selected[$Index]
        foreach ($Edge in $Edges) {
            if ($Edge.FromId -cne $Id) { continue }
            foreach ($RootId in $RootSets[$Id]) { [void]$RootSets[$Edge.ToId].Add($RootId) }
        }
    }
    $Components = [Collections.Generic.List[object]]::new()
    $Files = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($Id in (Get-InventoryOrder $Selected)) {
        $Record = $Context.Validated.Catalog[$Id]
        $Raw = $Context.Raw[$Id]
        $Folder = $Context.Native[$Id]
        $Sidecar = "$Folder/skill.metadata.yaml"
        $LicenseSource = if ($Raw.ContainsKey('license')) { $Sidecar } else { '.config/skill-library.yaml' }
        $LicenseOrigin = if ($Raw.ContainsKey('license')) { 'component' } else { 'repository-default' }
        $Notices = [Collections.Generic.List[object]]::new()
        $DefaultNotices = @(if ($Context.RawDefaults.ContainsKey('notices')) { $Context.RawDefaults.notices })
        for ($Index = 0; $Index -lt $DefaultNotices.Count; $Index++) {
            $Notices.Add([pscustomobject]@{ Path = $DefaultNotices[$Index]; SourcePath = '.config/skill-library.yaml'; Field = "notices[$Index]"; Origin = 'repository-default' })
        }
        $Additional = @(if ($Raw.ContainsKey('notices')) { $Raw.notices })
        for ($Index = 0; $Index -lt $Additional.Count; $Index++) {
            $Notices.Add([pscustomobject]@{ Path = $Additional[$Index]; SourcePath = $Sidecar; Field = "notices[$Index]"; Origin = 'component' })
        }
        $Components.Add([pscustomobject]@{
            Id = $Id; Version = $Record.version; NativeFolder = $Folder; Entrypoint = "$Folder/SKILL.md"; SourceCommit = $Context.Commit
            RootIds = (Get-InventoryOrder @($RootSets[$Id]))
            Reasons = (Get-InventoryReasonOrder -Reasons $ComponentReasons[$Id].ToArray() -Fields @('Kind', 'FromId', 'ToId', 'SourcePath', 'Field', 'SelectionKey', 'NativeFolder'))
            License = [pscustomobject]@{ Value = $Record.license; SourcePath = $LicenseSource; Field = 'license'; Origin = $LicenseOrigin }
            Notices = $Notices.ToArray()
        })
        foreach ($Path in $Context.Eligible) {
            if (-not $Path.StartsWith("$Folder/", [StringComparison]::Ordinal)) { continue }
            Add-InventoryFileReason $Context $Files $Path ([pscustomobject]@{ ComponentId = $Id; Kind = 'internal-content'; SourcePath = $Folder; Field = 'implicit-directory' })
        }
        foreach ($Notice in $Notices) {
            $Kind = if ($Notice.Origin -eq 'repository-default') { 'inherited-notice' } else { 'component-notice' }
            Add-InventoryFileReason $Context $Files $Notice.Path ([pscustomobject]@{ ComponentId = $Id; Kind = $Kind; SourcePath = $Notice.SourcePath; Field = $Notice.Field })
        }
        for ($Index = 0; $Index -lt $Record.externalFiles.Count; $Index++) {
            $External = $Record.externalFiles[$Index]
            Add-InventoryFileReason $Context $Files $External.path ([pscustomobject]@{
                ComponentId = $Id; Kind = "external-$($External.kind)"; SourcePath = $Sidecar
                Field = "externalFiles[$Index]"; LoadingPurpose = $External.loadingPurpose
            })
        }
    }
    $Entries = [Collections.Generic.List[object]]::new()
    foreach ($Path in (Get-InventoryOrder @($Files.Keys))) {
        $File = $Files[$Path]
        $Entries.Add([pscustomobject]@{
            Path = $Path; SourceCommit = $File.SourceCommit; Mode = $File.Mode
            Owners = (Get-InventoryOrder @($File.Owners))
            Reasons = (Get-InventoryReasonOrder -Reasons $File.Reasons.ToArray() -Fields @('ComponentId', 'Kind', 'SourcePath', 'Field', 'LoadingPurpose'))
        })
    }
    return [pscustomobject]@{
        SourceCommit = $Context.Commit; ValidationRules = 'invoked-tool-bundle'
        Roots = $Context.Roots; OptionalSelections = $Context.OptionalSelections
        Components = $Components.ToArray(); Files = $Entries.ToArray()
        Limitations = @(
            'Local changes and edits are excluded; only the chosen committed snapshot is inventoried.'
            'This is not a package, immutable provenance, installation state, release or publication evidence, rights clearance or delivery approval.'
        )
    }
}

function Get-SkillCommittedSelection {
    param([string]$RepoRoot, [string]$SourceRevision = 'HEAD', [string]$SkillName, [string[]]$OptionalSelection = @(), [string]$PythonPath = 'python3')
    Invoke-InventoryInspection -RepoRoot $RepoRoot -SourceRevision $SourceRevision -SkillName @($SkillName) -OptionalSelection $OptionalSelection -PythonPath $PythonPath -Inspect {
        param($Snapshot)
        $Inventory = New-InventoryResult $Snapshot
        $RootId = $Snapshot.Validated.Folders[$Snapshot.Roots[0]]
        $Root = [pscustomobject]@{
            Id = $RootId; Version = $Snapshot.Validated.Catalog[$RootId].version; Folder = $Snapshot.Native[$RootId]
        }
        $Payload = @(
            foreach ($File in $Inventory.Files) {
                $Bytes = Invoke-InventoryGitRead $Snapshot @('cat-file', 'blob', $Snapshot.Entries[$File.Path].Object) -Bytes
                [pscustomobject]@{
                    SourcePath = $File.Path; MemberPath = "payload/$($File.Path)"; Mode = $File.Mode
                    Size = $Bytes.LongLength; Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
                    Owners = @($File.Owners); Reasons = @($File.Reasons)
                }
            }
        )
        $Offers = @(
            foreach ($Component in $Inventory.Components) {
                $Record = $Snapshot.Validated.Catalog[$Component.Id]
                for ($Index = 0; $Index -lt $Record.optional.Count; $Index++) {
                    $Offer = $Record.optional[$Index]
                    [pscustomobject]@{
                        DeclaringId = $Component.Id; SelectionKey = $Offer.selectionKey
                        Selection = "$($Component.Id)/$($Offer.selectionKey)"; TargetId = $Offer.id
                        Version = $Offer.version; NativeFolder = $Snapshot.Native[$Offer.id]; Reason = $Offer.reason
                        SourcePath = "$($Component.NativeFolder)/skill.metadata.yaml"; OptionalIndex = $Index; Selected = "$($Component.Id)/$($Offer.selectionKey)" -cin $Snapshot.OptionalSelections
                    }
                }
            }
        )
        $ExtensionRoots = @($Root) + @(
            foreach ($Id in (Get-InventoryOrder @($Offers | Where-Object Selected | Select-Object -ExpandProperty TargetId -Unique))) {
                if ($Id -ceq $RootId) { continue }
                [pscustomobject]@{ Id = $Id; Version = $Snapshot.Validated.Catalog[$Id].version; Folder = $Snapshot.Native[$Id] }
            }
        )
        if ($ExtensionRoots.Count -gt 16) { throw 'At most 16 distinct extension roots may be selected.' }
        $Tools = @(
            foreach ($Relative in @('scripts/Invoke-Validation.ps1', 'scripts/Read-Metadata.py', 'scripts/Git-Process.ps1', 'skill-metadata.schema.json', 'repository-defaults.schema.json')) {
                $Bytes = [IO.File]::ReadAllBytes((Join-Path $Snapshot.Rules $Relative))
                [pscustomobject]@{
                    Role = 'inventory-rule'; Path = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../$Relative"))
                    Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
                }
            }
        )
        [pscustomobject]@{
            SourceCommit = $Snapshot.Commit; Root = $Root; OptionalSelection = @($Snapshot.OptionalSelections)
            ActiveComponents = @($Inventory.Components); ExtensionRoots = $ExtensionRoots
            Inventory = $Inventory; Payload = $Payload; OptionalOffers = $Offers; Tools = $Tools
        }
    }
}

function Invoke-SkillInventoryPreview {
    param(
        [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'), [string]$SourceRevision = 'HEAD',
        [string[]]$SkillName = @(), [string[]]$OptionalSelection = @(), [string]$PythonPath = 'python3'
    )
    Invoke-InventoryInspection -RepoRoot $RepoRoot -SourceRevision $SourceRevision -SkillName $SkillName -OptionalSelection $OptionalSelection -PythonPath $PythonPath -Inspect { param($Snapshot) New-InventoryResult $Snapshot }
}
#endregion

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Arguments = @{} + $PSBoundParameters
        $Arguments['RepoRoot'] = $RepoRoot
        $Result = Invoke-SkillInventoryPreview @Arguments
        ConvertTo-Json -InputObject $Result -Depth 64
        exit 0
    }
    catch {
        $Message = $_.Exception.Message
        if ($Message -notmatch '^(Prerequisite|Source|Validation|Eligibility|Inspection|Cleanup):') {
            $Message = 'Inspection: Restore readable safe local source and trusted tooling.'
        }
        [Console]::Error.WriteLine($Message)
        exit 1
    }
}
#endregion
