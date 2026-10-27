#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Validate opted-in skill metadata and selected dependency closure without writes.
.DESCRIPTION
Use the bundled schemas, repository defaults, restricted PyYAML reader and local filesystem checks.
Directories without skill.metadata.yaml are not opted in. No tooling is installed or executed.
.PARAMETER RepoRoot
Repository root. Defaults to the repository containing this script, independent of caller location.
.PARAMETER SkillName
Native folder names to select as roots. Empty selects every opted-in skill.
.PARAMETER OptionalSelection
Explicit optional edges as component-id/selectionKey; only reachable selections are accepted.
.PARAMETER PythonPath
Existing Python 3.11+ executable with the pinned PyYAML prerequisite. Defaults to python3.
.EXAMPLE
./Invoke-Validation.ps1 -SkillName patterns-ports-and-adapters -PythonPath /path/to/python
.NOTES
Requires PowerShell 7.4+, Python 3.11+ and PyYAML 6.0.3. Never installs prerequisites.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'),
    [string[]]$SkillName = @(),
    [string[]]$OptionalSelection = @(),
    [string]$PythonPath = 'python3'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

#region Functions
function Read-SkillYaml {
    param([string]$Path, [string]$PythonPath, [switch]$Frontmatter)
    try { $Executable = (Get-Command $PythonPath -CommandType Application -TotalCount 1).Source }
    catch { throw 'Python unavailable: pass -PythonPath pointing to Python 3.11+ with PyYAML 6.0.3.' }
    $Start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $Start.UseShellExecute = $false
    $Start.RedirectStandardOutput = $true
    $Start.RedirectStandardError = $true
    $Start.Environment['PYTHONDONTWRITEBYTECODE'] = '1'
    $Start.ArgumentList.Add('-I')
    $Start.ArgumentList.Add('-B')
    $Start.ArgumentList.Add((Join-Path $PSScriptRoot 'Read-Metadata.py'))
    $Start.ArgumentList.Add($Path)
    if ($Frontmatter) { $Start.ArgumentList.Add('--frontmatter') }
    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $Start
    try {
        [void]$Process.Start()
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.WaitForExit()
        $OutputText = $OutputTask.GetAwaiter().GetResult()
        [void]$ErrorTask.GetAwaiter().GetResult()
        if ($Process.ExitCode -ne 0) {
            throw 'YAML reader failed: check Python/PyYAML prerequisites and restricted single-document YAML; remove duplicate keys, aliases, tags and non-JSON types.'
        }
        return ConvertFrom-Json -InputObject $OutputText -AsHashtable -NoEnumerate -Depth 64
    }
    finally { $Process.Dispose() }
}

function Assert-LibraryPath {
    param([string]$Root, [string]$Relative, [switch]$Directory)
    if ($Relative -notmatch '^(?!/)(?!.*(?:^|/)\.\.?(?:/|$))(?!.*[\\:\x00-\x1f])[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$') {
        throw 'Unsafe path: use repository-relative POSIX segments without traversal.'
    }
    $Current = $Root
    foreach ($Segment in $Relative.Split('/')) {
        if ($Segment -match '^(?i:\.env(?:\..*)?|.*\.(?:pem|key|pfx|p12)|secrets?(?:\..*)?|\.git|__pycache__|node_modules)$') {
            throw 'Unsafe local input name: remove secret, cache or local environment inputs from opted-in content.'
        }
        $Current = Join-Path $Current $Segment
        if (-not (Test-Path -LiteralPath $Current)) { throw 'Missing declared path: provide the referenced file or directory.' }
        $Item = Get-Item -LiteralPath $Current -Force
        if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Unsafe symbolic link: opted-in inputs and their ancestors must be regular files or directories.'
        }
    }
    if ($Directory -ne [bool]$Item.PSIsContainer) { throw 'Declared path has the wrong file/directory kind.' }
    return $Current
}

function Assert-SkillTree {
    param([string]$Root, [string]$Relative, [System.Collections.Generic.HashSet[string]]$Paths)
    $Folder = Assert-LibraryPath -Root $Root -Relative $Relative -Directory
    foreach ($Item in Get-ChildItem -LiteralPath $Folder -Force) {
        $Child = "$Relative/$($Item.Name)"
        [void](Assert-LibraryPath -Root $Root -Relative $Child -Directory:$Item.PSIsContainer)
        if (-not $Paths.Add($Child)) { throw 'Case-insensitive path collision: rename colliding opted-in inputs.' }
        if ($Item.PSIsContainer) { Assert-SkillTree -Root $Root -Relative $Child -Paths $Paths }
    }
}

function Invoke-SkillValidation {
    param(
        [string]$RepoRoot, [string[]]$SkillName = @(), [string[]]$OptionalSelection = @(),
        [string]$PythonPath = 'python3', [switch]$IncludeCatalog
    )
    $Root = (Resolve-Path -LiteralPath $RepoRoot).Path
    if ((Get-Item -LiteralPath $Root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Repository root must not be a symbolic link.'
    }
    $SkillsRoot = Assert-LibraryPath -Root $Root -Relative '.github/skills' -Directory
    $Schema = Join-Path $PSScriptRoot '../skill-metadata.schema.json'
    $DefaultsPath = Assert-LibraryPath -Root $Root -Relative '.config/skill-library.yaml'
    $Defaults = Read-SkillYaml -Path $DefaultsPath -PythonPath $PythonPath
    $DefaultsJson = ConvertTo-Json -InputObject $Defaults -Depth 64 -Compress
    if (-not (Test-Json -Json $DefaultsJson -SchemaFile (Join-Path $PSScriptRoot '../repository-defaults.schema.json') -ErrorAction SilentlyContinue)) {
        throw 'Repository defaults schema validation failed: declare a license and optional notice array using the bundled schema.'
    }
    if (-not $Defaults.ContainsKey('notices')) { $Defaults['notices'] = @() }
    $DefaultPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Notice in $Defaults.notices) {
        if (-not $DefaultPaths.Add($Notice)) { throw 'Duplicate declared path in repository defaults.' }
        [void](Assert-LibraryPath -Root $Root -Relative $Notice)
    }
    $Catalog = @{}
    $Folders = @{}
    $Paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Folder in Get-ChildItem -LiteralPath $SkillsRoot -Directory -Force | Sort-Object Name) {
        $MetadataPath = Join-Path $Folder.FullName 'skill.metadata.yaml'
        if (-not (Test-Path -LiteralPath $MetadataPath)) { continue }
        $Relative = ".github/skills/$($Folder.Name)"
        [void](Assert-LibraryPath -Root $Root -Relative "$Relative/skill.metadata.yaml")
        $Record = Read-SkillYaml -Path $MetadataPath -PythonPath $PythonPath
        $Json = ConvertTo-Json -InputObject $Record -Depth 64 -Compress
        if (-not (Test-Json -Json $Json -SchemaFile $Schema -ErrorAction SilentlyContinue)) {
            throw 'Metadata schema validation failed: check required fields, closed objects, versions and collection types against the bundled schema.'
        }
        foreach ($Collection in @('facets', 'notices', 'required', 'optional', 'externalFiles', 'tooling')) {
            if (-not $Record.ContainsKey($Collection)) { $Record[$Collection] = @() }
        }
        if (-not $Record.ContainsKey('license')) { $Record['license'] = $Defaults.license }
        if ($Catalog.ContainsKey($Record.id)) { throw 'Duplicate component ID: give each opted-in skill a distinct id.' }
        $Entry = Assert-LibraryPath -Root $Root -Relative "$Relative/SKILL.md"
        $Native = Read-SkillYaml -Path $Entry -PythonPath $PythonPath -Frontmatter
        if ($Native -isnot [System.Collections.IDictionary] -or -not $Native.ContainsKey('name') -or
            $Native.name -cne $Folder.Name -or -not $Native.ContainsKey('description') -or
            $Native.description -isnot [string] -or [string]::IsNullOrWhiteSpace($Native.description)) {
            throw 'Native frontmatter must have a matching folder/name and a nonempty description.'
        }
        Assert-SkillTree -Root $Root -Relative $Relative -Paths $Paths
        if (-not $Paths.Add($Relative)) { throw 'Case-insensitive skill folder collision.' }
        $Declared = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($Notice in $Defaults.notices) { [void]$Declared.Add($Notice) }
        foreach ($Notice in $Record.notices) {
            if (-not $Declared.Add($Notice)) { throw 'Duplicate declared path.' }
            [void](Assert-LibraryPath -Root $Root -Relative $Notice)
        }
        $Record.notices = @($Defaults.notices) + @($Record.notices)
        foreach ($External in $Record.externalFiles) {
            if ($External.path.StartsWith("$Relative/", [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Internal skill files are implicit content, not externalFiles declarations.'
            }
            if (-not $Declared.Add($External.path)) { throw 'Duplicate declared path.' }
            [void](Assert-LibraryPath -Root $Root -Relative $External.path)
        }
        $Tools = @{}
        foreach ($Tool in $Record.tooling) {
            $Key = "$($Tool.scope)/$($Tool.id)"
            if ($Tools.ContainsKey($Key)) { throw 'Duplicate tooling declaration.' }
            $Tools[$Key] = $true
        }
        $Catalog[$Record.id] = $Record
        $Folders[$Folder.Name] = $Record.id
    }
    if ($Catalog.Count -eq 0) { throw 'No opted-in skill.metadata.yaml records found.' }
    $Selections = @{}
    foreach ($Record in $Catalog.Values) {
        $Edges = @{}
        foreach ($Edge in @($Record.required) + @($Record.optional)) {
            if ($Edges.ContainsKey($Edge.id)) { throw 'Duplicate dependency or required/optional overlap.' }
            $Edges[$Edge.id] = $true
            if (-not $Catalog.ContainsKey($Edge.id)) { throw 'Missing dependency: opt in the target component with metadata.' }
            if ($Catalog[$Edge.id].version -cne $Edge.version) { throw 'Dependency version mismatch: declare an available exact version.' }
        }
        foreach ($Edge in $Record.optional) {
            $Key = "$($Record.id)/$($Edge.selectionKey)"
            if ($Selections.ContainsKey($Key)) { throw 'Duplicate optional selection key.' }
            $Selections[$Key] = $Edge.id
        }
    }
    $Chosen = @{}
    foreach ($Key in $OptionalSelection) {
        if (-not $Selections.ContainsKey($Key) -or $Chosen.ContainsKey($Key)) { throw 'Unknown or duplicate optional selection: use component-id/selectionKey.' }
        $Chosen[$Key] = $false
    }
    $State = @{}
    $Resolved = [System.Collections.Generic.List[string]]::new()
    function Resolve-SkillDependency {
        param([string]$Id, [bool]$IncludeOptional)
        if ($State.ContainsKey($Id)) {
            if ($State[$Id] -eq 'visiting') { throw 'Dependency cycle detected in selected closure.' }
            return
        }
        $State[$Id] = 'visiting'
        $Record = $Catalog[$Id]
        foreach ($Edge in $Record.required) { Resolve-SkillDependency -Id $Edge.id -IncludeOptional $IncludeOptional }
        if ($IncludeOptional) {
            foreach ($Edge in $Record.optional) {
                $Key = "$Id/$($Edge.selectionKey)"
                if ($Chosen.ContainsKey($Key)) {
                    $Chosen[$Key] = $true
                    Resolve-SkillDependency -Id $Edge.id -IncludeOptional $true
                }
            }
        }
        $State[$Id] = 'done'
        $Resolved.Add($Id)
    }
    foreach ($Id in @($Catalog.Keys | Sort-Object)) { Resolve-SkillDependency -Id $Id -IncludeOptional $false }
    $State.Clear()
    $Resolved.Clear()
    $Roots = @($Catalog.Keys | Sort-Object)
    if ($SkillName.Count -gt 0) {
        $Roots = @(foreach ($Name in $SkillName) {
            if (-not $Folders.ContainsKey($Name)) { throw 'Selected native skill is missing or has not opted in.' }
            $Folders[$Name]
        })
    }
    foreach ($Id in $Roots) { Resolve-SkillDependency -Id $Id -IncludeOptional $true }
    if (@($Chosen.Values | Where-Object { -not $_ }).Count -gt 0) { throw 'Optional selection is not reachable from the selected roots.' }
    $Result = [ordered]@{ CatalogCount = $Catalog.Count; SelectedIds = $Resolved.ToArray() }
    if ($IncludeCatalog) {
        $Result['Catalog'] = $Catalog
        $Result['Folders'] = $Folders
        $Result['Defaults'] = $Defaults
    }
    [pscustomobject]$Result
}
#endregion

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Arguments = @{} + $PSBoundParameters
        $Arguments['RepoRoot'] = $RepoRoot
        Invoke-SkillValidation @Arguments
        exit 0
    }
    catch {
        Write-Error -Message "Skill validation failed: $($_.Exception.Message)" -ErrorAction Continue
        exit 1
    }
}
#endregion
