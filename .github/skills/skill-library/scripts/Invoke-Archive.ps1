#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Build one committed skill's required-only deterministic archive.
.DESCRIPTION
Use the invoked trusted inventory bundle and an isolated local writer. Loading this file is inert.
.PARAMETER RepoRoot
Actual local source repository; defaults to the invoked tool's repository.
.PARAMETER SourceRevision
Locally available commit, default HEAD.
.PARAMETER SkillName
Exactly one explicit native skill folder name.
.PARAMETER OutputDirectory
New absolute destination beneath an existing trusted parent outside source and Git directories.
.PARAMETER PythonPath
Existing CPython 3.11+ with PyYAML 6.0.3. No provisioning is performed.
.EXAMPLE
./Invoke-Archive.ps1 -SkillName example -OutputDirectory /tmp/new-archive -PythonPath /path/to/python
.NOTES
No optional bundles, installation, version preparation or publication.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'),
    [string]$SourceRevision = 'HEAD',
    [string[]]$SkillName = @(),
    [string]$OutputDirectory = '',
    [string]$PythonPath = 'python3'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

#region Functions
function Assert-ArchiveDirectory {
    param([string]$Path, [string[]]$Excluded = @())
    if (-not [IO.Path]::IsPathFullyQualified($Path) -or $Path.Split('/') -contains '..' -or $Path.Split('/') -contains '.') {
        throw 'Output: Use an unambiguous absolute path.'
    }
    $Full = [IO.Path]::GetFullPath($Path).TrimEnd('/')
    foreach ($Boundary in $Excluded) {
        if ($Full -ceq $Boundary -or $Full.StartsWith($Boundary.TrimEnd('/') + '/', [StringComparison]::Ordinal)) {
            throw 'Output: Temporary and output storage must be outside source and Git directories.'
        }
    }
    $Ancestor = Get-Item -LiteralPath $Full -Force
    while ($null -ne $Ancestor) {
        if ($Ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Output: Linked storage ancestry is not supported.' }
        $Ancestor = $Ancestor.Parent
    }
    return $Full
}

function Copy-ArchiveBundle {
    param([string]$Destination)
    $BundleRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $Paths = @(
        'repository-defaults.schema.json', 'scripts/Git-Process.ps1', 'scripts/Invoke-Archive.ps1',
        'scripts/Invoke-InventoryPreview.ps1', 'scripts/Invoke-Validation.ps1', 'scripts/Read-Metadata.py',
        'scripts/Write-Archive.py', 'scripts/requirements.txt', 'skill-metadata.schema.json'
    )
    $Captured = @{}
    foreach ($Path in $Paths) {
        $Source = Join-Path $BundleRoot $Path
        [void](Assert-ArchiveDirectory -Path ([IO.Path]::GetDirectoryName($Source)))
        $Item = Get-Item -LiteralPath $Source -Force
        if ($Item -isnot [IO.FileInfo] -or $Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Inspection: Unsafe trusted bundle input.' }
        $Captured[$Path] = [IO.File]::ReadAllBytes($Source)
    }
    $Files = [Collections.Generic.List[object]]::new()
    foreach ($Path in $Paths) {
        $Current = [IO.File]::ReadAllBytes((Join-Path $BundleRoot $Path))
        if ([Convert]::ToBase64String($Captured[$Path]) -cne [Convert]::ToBase64String($Current)) {
            throw 'Inspection: Trusted bundle changed during capture.'
        }
        $Target = Join-Path $Destination $Path
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
        [IO.File]::WriteAllBytes($Target, $Captured[$Path])
        $Files.Add([pscustomobject]@{ Path = $Path; Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Captured[$Path])).ToLowerInvariant() })
    }
    return ,$Files.ToArray()
}

function Remove-ArchiveScratch {
    param([string]$Path)
    if ([IO.Directory]::Exists($Path)) { [IO.Directory]::Delete($Path, $true) }
}

function Invoke-ArchiveCaptured {
    param([object]$Request)
    . (Join-Path $Request.Rules 'scripts/Invoke-InventoryPreview.ps1')
    $Inventory = Invoke-SkillInventoryPreview -RepoRoot $Request.Root -SourceRevision $Request.Commit -SkillName @($Request.Name) -OptionalSelection @() -PythonPath $Request.Python
    if ($Inventory.SourceCommit -cne $Request.Commit -or $Inventory.ValidationRules -cne 'invoked-tool-bundle' -or
        $Inventory.Roots.Count -ne 1 -or $Inventory.Roots[0] -cne $Request.Name -or $Inventory.OptionalSelections.Count -ne 0) {
        throw 'Inspection: Inventory does not match the frozen required-only request.'
    }
    foreach ($Component in $Inventory.Components) {
        if ($Component.SourceCommit -cne $Request.Commit -or @($Component.Reasons | Where-Object Kind -NotIn @('root', 'required')).Count) {
            throw 'Inspection: Inventory contains non-required component evidence.'
        }
    }
    $Roots = @($Inventory.Components | Where-Object NativeFolder -CEQ ".github/skills/$($Request.Name)")
    if ($Roots.Count -ne 1) { throw 'Selection: The selected root must resolve to one opted-in component.' }
    $RootRecord = [pscustomobject]@{ Id = $Roots[0].Id; Version = $Roots[0].Version; Folder = $Roots[0].NativeFolder }
    $Stage = Join-Path $Request.Scratch 'payload'
    [void][IO.Directory]::CreateDirectory($Stage)
    $Records = [Collections.Generic.List[object]]::new()
    $Seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($File in $Inventory.Files) {
        if ($File.SourceCommit -cne $Request.Commit -or -not $Seen.Add($File.Path)) { throw 'Inspection: Duplicate or mismatched inventory source.' }
        $Tree = Invoke-LibraryGit -Root $Request.Root -Arguments @('ls-tree', '-z', $Request.Commit, '--', $File.Path)
        if ($Tree.ExitCode -ne 0 -or $Tree.Error) { throw 'Source: Committed tree inspection failed.' }
        $Rows = [Text.UTF8Encoding]::new($false, $true).GetString($Tree.Bytes).Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)
        if ($Rows.Count -ne 1) { throw 'Source: Missing or ambiguous committed payload file.' }
        $Fields = $Rows[0].Split("`t", 2)
        $Header = $Fields[0].Split(' ')
        if ($Fields.Count -ne 2 -or $Fields[1] -cne $File.Path -or $Header.Count -ne 3 -or
            $Header[0] -cne $File.Mode -or $Header[0] -notin @('100644', '100755') -or $Header[1] -cne 'blob') {
            throw 'Source: Committed payload path, type or mode does not match inventory.'
        }
        $Blob = Invoke-LibraryGit -Root $Request.Root -Arguments @('cat-file', 'blob', $Header[2])
        if ($Blob.ExitCode -ne 0 -or $Blob.Error) { throw 'Source: Committed payload blob is unavailable locally.' }
        $StagedPath = Join-Path $Stage ([string]$Records.Count)
        [IO.File]::WriteAllBytes($StagedPath, $Blob.Bytes)
        $Records.Add([pscustomobject]@{
            SourcePath = $File.Path; MemberPath = "payload/$($File.Path)"; Mode = $File.Mode
            Size = $Blob.Bytes.LongLength; Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Blob.Bytes)).ToLowerInvariant()
            Owners = @($File.Owners); Reasons = @($File.Reasons); StagedPath = $StagedPath
        })
    }
    $Handoff = [pscustomobject]@{
        SourceCommit = $Request.Commit; Root = $RootRecord; Builder = $Request.Builder
        Components = @($Inventory.Components); Payload = $Records.ToArray(); Destination = $Request.Output
        Boundaries = $Request.Boundaries; Scratch = $Request.Scratch
    }
    Invoke-ArchiveWriter -Request $Request -Handoff $Handoff
}

function Read-ArchiveWriterMessage {
    param([object]$Process, [string]$Destination, [string]$Category = 'Archive')
    try {
        $Line = $Process.StandardOutput.ReadLine()
        if ([string]::IsNullOrWhiteSpace($Line)) { throw 'Missing acknowledgment.' }
        $Message = ConvertFrom-Json -InputObject $Line
        if ($null -eq $Message -or $Message.Status -notin @('Prepared', 'Completed', 'Failed')) { throw 'Invalid acknowledgment.' }
        return $Message
    }
    catch { throw "${Category}: Writer acknowledgment failed; inspect $Destination for recovery. No success is reported." }
}

function Invoke-ArchiveWriter {
    param([object]$Request, [object]$Handoff)
    $Start = [Diagnostics.ProcessStartInfo]::new($Request.Python)
    $Start.UseShellExecute = $false
    $Start.RedirectStandardInput = $true
    $Start.RedirectStandardOutput = $true
    $Start.RedirectStandardError = $true
    $Start.StandardInputEncoding = [Text.UTF8Encoding]::new($false, $true)
    foreach ($Argument in @('-I', '-B', (Join-Path $Request.Rules 'scripts/Write-Archive.py'))) { $Start.ArgumentList.Add($Argument) }
    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $Start
    $Started = $false
    try {
        [void]$Process.Start()
        $Started = $true
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.StandardInput.WriteLine((ConvertTo-Json -InputObject $Handoff -Depth 64 -Compress))
        $Message = Read-ArchiveWriterMessage -Process $Process -Destination $Request.Output
        if ($Message.Status -eq 'Failed') {
            $Category = if ($Message.Category -match '^(Prerequisite|Selection|Source|Validation|Eligibility|Inspection|Archive|Output|Cleanup)$') { $Message.Category } else { 'Archive' }
            throw "${Category}: No archive was completed. Inspect destination $($Request.Output) for retained recovery material."
        }
        if ($Message.Status -cne 'Prepared') { throw 'Archive: Writer protocol mismatch.' }
        try { Remove-ArchiveScratch -Path $Request.Scratch }
        catch { throw "Cleanup: Temporary data retained at $($Request.Scratch); inspect $($Request.Output). No success is reported." }
        $Process.StandardInput.WriteLine('finalize')
        $Process.StandardInput.Close()
        $Completion = Read-ArchiveWriterMessage -Process $Process -Destination $Request.Output -Category Cleanup
        if ($null -eq $Completion -or $Completion.Status -cne 'Completed') {
            throw "Cleanup: Writer finalization was not acknowledged; inspect $($Request.Output) for recovery. No success is reported."
        }
        $Remaining = $Process.StandardOutput.ReadToEnd()
        $Process.WaitForExit()
        $ErrorText = $ErrorTask.GetAwaiter().GetResult()
        if ($Process.ExitCode -ne 0 -or $ErrorText -or $Remaining) { throw "Cleanup: Writer exit was not clean; inspect $($Request.Output). No success is reported." }
        $Result = $Completion.Result
        if ($Result.SourceCommit -cne $Request.Commit -or $Result.OutputDirectory -cne $Request.Output -or
            $Result.ArchiveContract -cne 'skill-archive/1' -or $Result.ArchiveSha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Archive: Writer result did not match the frozen request.'
        }
        return $Result
    }
    finally {
        if ($Started) {
            if (-not $Process.HasExited) { $Process.StandardInput.Close(); $Process.WaitForExit() }
        }
        $Process.Dispose()
    }
}

function Invoke-SkillArchive {
    [CmdletBinding()]
    param(
        [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'),
        [string]$SourceRevision = 'HEAD',
        [string[]]$SkillName = @(),
        [string]$OutputDirectory = '',
        [string]$PythonPath = 'python3'
    )
    $Scratch = $null
    $Category = 'Prerequisite'
    try {
        if (-not $IsLinux) { throw 'Prerequisite: Archive construction currently requires Linux.' }
        $Category = 'Selection'
        if ($SkillName.Count -ne 1 -or $SkillName[0] -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw 'Selection: Supply exactly one explicit native skill folder.'
        }
        if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'Output: Supply a new absolute output directory.' }
        $Category = 'Prerequisite'
        $Python = (Get-Command $PythonPath -CommandType Application -TotalCount 1).Source
        . (Join-Path $PSScriptRoot 'Git-Process.ps1')
        $Probe = Invoke-LibraryProcess -Executable $Python -Arguments @('-I', '-B', '-c', 'import json,platform,sys,yaml; assert sys.platform == "linux" and platform.python_implementation() == "CPython" and sys.version_info >= (3,11) and yaml.__version__ == "6.0.3"; print(json.dumps({"Python":{"Implementation":platform.python_implementation(),"Version":platform.python_version()},"PyYAML":yaml.__version__}))')
        if ($Probe.ExitCode -ne 0 -or $Probe.Error) { throw 'Prerequisite: Supply existing Linux CPython 3.11+ with PyYAML 6.0.3.' }
        $Runtimes = [Text.Encoding]::UTF8.GetString($Probe.Bytes) | ConvertFrom-Json -AsHashtable
        $Runtimes['PowerShell'] = $PSVersionTable.PSVersion.ToString()
        $GitVersion = Invoke-LibraryProcess -Executable (Get-Command git -CommandType Application -TotalCount 1).Source -Arguments @('--version')
        if ($GitVersion.ExitCode -ne 0 -or $GitVersion.Error) { throw 'Prerequisite: Supply installed Git.' }
        $Runtimes['Git'] = [Text.Encoding]::UTF8.GetString($GitVersion.Bytes).Trim()
        $Category = 'Source'
        $Root = Assert-ArchiveDirectory -Path ([IO.Path]::GetFullPath($RepoRoot))
        $Boundaries = [Collections.Generic.List[string]]::new()
        $Boundaries.Add($Root)
        foreach ($Arguments in @(@('rev-parse', '--show-toplevel'), @('rev-parse', '--path-format=absolute', '--git-dir'), @('rev-parse', '--path-format=absolute', '--git-common-dir'))) {
            $Read = Invoke-LibraryGit -Root $Root -Arguments $Arguments
            if ($Read.ExitCode -ne 0 -or $Read.Error) { throw 'Source: Supply the actual local repository root.' }
            $Path = [Text.UTF8Encoding]::new($false, $true).GetString($Read.Bytes).TrimEnd("`n", "`r")
            if ($Arguments -contains '--show-toplevel' -and $Path -cne $Root) { throw 'Source: Supply the actual local repository root.' }
            $Boundaries.Add([IO.Path]::GetFullPath($Path).TrimEnd('/'))
        }
        $Revision = Invoke-LibraryGit -Root $Root -Arguments @('rev-parse', '--verify', '--end-of-options', "$SourceRevision^{commit}")
        if ($Revision.ExitCode -ne 0 -or $Revision.Error) { throw 'Source: Supply a locally available unambiguous commit.' }
        $Commit = [Text.Encoding]::UTF8.GetString($Revision.Bytes).TrimEnd("`n", "`r")
        if ($Commit -cnotmatch '^[0-9a-f]{40,64}$') { throw 'Source: Invalid local commit identity.' }
        $Category = 'Output'
        $Parent = Assert-ArchiveDirectory -Path ([IO.Path]::GetDirectoryName($OutputDirectory)) -Excluded $Boundaries.ToArray()
        if ($OutputDirectory.Split('/') -contains '..' -or $OutputDirectory.Split('/') -contains '.' -or -not [IO.Path]::IsPathFullyQualified($OutputDirectory)) {
            throw 'Output: Use an unambiguous absolute path.'
        }
        $Output = [IO.Path]::GetFullPath($OutputDirectory)
        foreach ($Boundary in $Boundaries) {
            if ($Output -ceq $Boundary -or $Output.StartsWith($Boundary + '/', [StringComparison]::Ordinal)) { throw 'Output: Destination is inside managed source or Git storage.' }
        }
        if (Get-Item -LiteralPath $Output -Force -ErrorAction SilentlyContinue) { throw 'Output: Destination already exists; choose a new path.' }
        $TemporaryParent = Assert-ArchiveDirectory -Path ([IO.Path]::GetTempPath()) -Excluded $Boundaries.ToArray()
        $Scratch = [IO.Directory]::CreateTempSubdirectory('skill-archive-').FullName
        [IO.File]::SetUnixFileMode($Scratch, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
        $Category = 'Inspection'
        $Rules = Join-Path $Scratch 'rules'
        $Files = Copy-ArchiveBundle -Destination $Rules
        $Request = [pscustomobject]@{
            Root = $Root; Commit = $Commit; Name = $SkillName[0]; Output = $Output; Python = $Python
            Boundaries = $Boundaries.ToArray(); Scratch = $Scratch; Rules = $Rules
            Builder = [pscustomobject]@{ Contract = 'skill-archive/1'; ValidationRules = 'invoked-tool-bundle'; Files = $Files; Runtimes = $Runtimes }
        }
        $Result = & {
            param($CapturedScript, $FrozenRequest)
            . $CapturedScript
            Invoke-ArchiveCaptured -Request $FrozenRequest
        } (Join-Path $Rules 'scripts/Invoke-Archive.ps1') $Request
    }
    catch {
        if ($_.Exception.Message -match '^(Prerequisite|Selection|Source|Validation|Eligibility|Inspection|Archive|Output|Cleanup):') { throw }
        throw "${Category}: No archive was completed; check local prerequisites, source and storage."
    }
    finally {
        if ($Scratch) {
            try { Remove-ArchiveScratch -Path $Scratch }
            catch { throw "Cleanup: Temporary data retained at $Scratch; no archive success is reported." }
        }
    }
    return $Result
}
#endregion

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Arguments = @{} + $PSBoundParameters
        $Arguments['RepoRoot'] = $RepoRoot
        $Result = Invoke-SkillArchive @Arguments
        ConvertTo-Json -InputObject $Result -Depth 64
        exit 0
    }
    catch {
        $Message = $_.Exception.Message
        if ($Message -notmatch '^(Prerequisite|Selection|Source|Validation|Eligibility|Inspection|Archive|Output|Cleanup):') { $Message = 'Archive: No archive was completed.' }
        [Console]::Error.WriteLine($Message)
        exit 1
    }
}
#endregion
