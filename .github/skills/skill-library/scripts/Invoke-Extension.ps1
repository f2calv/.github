#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Adapt one verified required-only skill archive into a local Spec Kit extension pilot.
.DESCRIPTION
Preserve canonical resources and source evidence; generate a thin read-only command and one catalog
entry for Spec Kit 1.2.3. No installation, hosting, publication or dependency resolution is performed.
.PARAMETER ArchivePath
Existing skill-archive/1 ZIP from the trusted local archive workflow, at most 64 MiB.
.PARAMETER ArchiveSha256
Expected SHA-256 obtained from that approved build, not inferred from untrusted content.
.PARAMETER OutputDirectory
New absolute directory under an existing trusted parent outside the source checkout. Linux only.
.PARAMETER BaseUri
Hosting base URI for the generated catalog: HTTPS or loopback HTTP, without credentials or queries.
.EXAMPLE
./Invoke-Extension.ps1 -ArchivePath /tmp/native/package.zip -ArchiveSha256 <digest> -OutputDirectory /tmp/site -BaseUri http://127.0.0.1:8123/
.NOTES
Use stable inputs and exclusive caller-owned output. Failure after reservation retains partial output
for deliberate recovery; never overwrite or adopt it. No hostile-writer or atomic-output guarantee.
#>
[CmdletBinding()]
param(
    [string]$ArchivePath = '',
    [string]$ArchiveSha256 = '',
    [string]$OutputDirectory = '',
    [string]$BaseUri = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$PSNativeCommandUseErrorActionPreference = $false

#region Functions
function Get-ExtensionDigest {
    param([byte[]]$Bytes)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-ExtensionJson {
    param([object]$Value)
    return ,([Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 60 -Compress) + "`n"))
}

function Invoke-SkillExtension {
    [CmdletBinding()]
    param(
        [string]$ArchivePath,
        [string]$ArchiveSha256,
        [string]$OutputDirectory,
        [string]$BaseUri
    )
    if (-not $IsLinux) { throw 'Input: This pilot adapter requires Linux.' }
    $Resources = [Collections.Generic.List[object]]::new()
    try {
        $Uri = [uri]::new($BaseUri, [UriKind]::Absolute)
        if ($Uri.Scheme -ne 'https' -and -not ($Uri.Scheme -eq 'http' -and $Uri.IsLoopback)) { throw 'Unsafe hosting URI.' }
        if ($Uri.UserInfo -or $Uri.Query -or $Uri.Fragment -or -not $Uri.AbsolutePath.EndsWith('/')) { throw 'Ambiguous hosting URI.' }
        if ($ArchiveSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Missing expected digest.' }
        $Input = Get-Item -LiteralPath $ArchivePath -Force
        if ($Input -isnot [IO.FileInfo] -or $Input.Length -gt 64MB -or $Input.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unsupported input.' }
        $InputBytes = [IO.File]::ReadAllBytes($Input.FullName)
        if ((Get-ExtensionDigest $InputBytes) -cne $ArchiveSha256) { throw 'Archive digest mismatch.' }
        $Memory = [IO.MemoryStream]::new($InputBytes, $false)
        $SourceZip = [IO.Compression.ZipArchive]::new($Memory, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $Seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Entry in $SourceZip.Entries) {
                if (-not $Seen.Add($Entry.FullName) -or $Entry.Length -gt 16MB) { throw 'Duplicate or oversized member.' }
            }
            $ManifestEntry = $SourceZip.GetEntry('manifest.json')
            if ($null -eq $ManifestEntry) { throw 'Missing source manifest.' }
            $Buffer = [IO.MemoryStream]::new()
            $Stream = $ManifestEntry.Open()
            try { $Stream.CopyTo($Buffer); $ManifestBytes = $Buffer.ToArray() }
            finally { $Stream.Dispose(); $Buffer.Dispose() }
            $Manifest = [Text.UTF8Encoding]::new($false, $true).GetString($ManifestBytes) | ConvertFrom-Json -AsHashtable -Depth 60
            if ($Manifest.SchemaVersion -ne 1 -or $Manifest.Builder.Contract -cne 'skill-archive/1' -or
                $Manifest.OptionalSelections.Count -ne 0 -or $Manifest.SourceCommit -cnotmatch '^([0-9a-f]{40}|[0-9a-f]{64})$') { throw 'Invalid source evidence.' }
            $Root = $Manifest.Root
            if ($Root.Id -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or $Root.Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or
                $Root.Folder -cnotmatch '^\.github/skills/[a-z0-9]+(-[a-z0-9]+)*$') { throw 'Invalid root identity.' }
            $RootComponents = @($Manifest.Components | Where-Object { $_.Id -ceq $Root.Id -and $_.Version -ceq $Root.Version -and $_.NativeFolder -ceq $Root.Folder })
            if ($RootComponents.Count -ne 1 -or @($Manifest.Components.Reasons | Where-Object Kind -NotIn @('root', 'required')).Count) { throw 'Invalid required-only components.' }
            if ($Manifest.Payload.Count -eq 0 -or $SourceZip.Entries.Count -ne $Manifest.Payload.Count + 1) { throw 'Unexpected source members.' }
            $Paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $TotalSize = 0L
            foreach ($Record in $Manifest.Payload) {
                $Path = $Record.SourcePath
                if ($Path -cnotmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$' -or $Path.Split('/') -contains '.' -or $Path.Split('/') -contains '..' -or
                    -not $Paths.Add($Path) -or $Record.MemberPath -cne "payload/$Path" -or $Record.Mode -notin @('100644', '100755')) { throw 'Unsafe source path or mode.' }
                $Entry = $SourceZip.GetEntry($Record.MemberPath)
                if ($null -eq $Entry -or $Entry.Length -ne $Record.Size -or $Entry.Length -gt 16MB) { throw 'Missing or inconsistent payload.' }
                $TotalSize += $Entry.Length
                if ($TotalSize -gt 64MB) { throw 'Pilot payload limit exceeded.' }
                $Buffer = [IO.MemoryStream]::new()
                $Stream = $Entry.Open()
                try { $Stream.CopyTo($Buffer); $Bytes = $Buffer.ToArray() }
                finally { $Stream.Dispose(); $Buffer.Dispose() }
                if ((Get-ExtensionDigest $Bytes) -cne $Record.Sha256) { throw 'Payload digest mismatch.' }
                $Resources.Add([pscustomobject]@{ Name = "resources/library/$Path"; Bytes = $Bytes; Mode = $Record.Mode })
            }
            if (-not $Paths.Contains("$($Root.Folder)/SKILL.md")) { throw 'Missing root skill.' }
        }
        finally { $SourceZip.Dispose(); $Memory.Dispose() }
    }
    catch { throw 'Input: Use a valid required-only skill-archive/1 build, its expected digest, and an HTTPS or loopback hosting base URI. No output was reserved.' }

    $Command = "speckit.$($Root.Id).load"
    $Description = "Load the packaged $($Root.Id) skill and its required resources."
    $Extension = [ordered]@{
        schema_version = '1.0'
        extension = [ordered]@{ id = $Root.Id; name = $Root.Id; version = $Root.Version; description = $Description; effect = 'read-only' }
        requires = @{ speckit_version = '==1.2.3' }
        provides = @{ commands = @(@{ name = $Command; file = 'commands/load.md'; description = $Description }) }
    }
    $Instructions = @($Manifest.Payload | Where-Object SourcePath -Like '*.instructions.md' | ForEach-Object { "- ``.specify/extensions/$($Root.Id)/resources/library/$($_.SourcePath)``" }) -join "`n"
    $Body = @'
---
description: __DESCRIPTION__
---

# Load Packaged Skill

User request: $ARGUMENTS

Work from the consumer workspace root. Read the installed canonical skill:
`.specify/extensions/__ID__/resources/library/__FOLDER__/SKILL.md`.

Read these bundled instructions before applying the skill; copying them here does not activate native applyTo rules:
__INSTRUCTIONS__

Resolve the skill's relative resource links relative to its installed containing file, beneath
`.specify/extensions/__ID__/resources/library/`. Read relevant references/examples on demand.
Never fall back to the original library checkout, a user-profile copy or uninstalled optional skills.
Report missing resources instead. Do not execute packaged scripts, edit files, install tools, download
optional extensions or make commits. This pilot command only reads guidance and answers the request.
Conclude with the installed workspace-relative paths actually read, distinguishing them from suggested
resources that were not read. File existence alone is not evidence that their guidance was loaded.

'@
    $Body = $Body.Replace('__DESCRIPTION__', ($Description | ConvertTo-Json -Compress)).Replace('__ID__', $Root.Id).Replace('__FOLDER__', $Root.Folder).Replace('__INSTRUCTIONS__', $Instructions)
    $Resources.Insert(0, [pscustomobject]@{ Name = 'commands/load.md'; Bytes = [Text.Encoding]::UTF8.GetBytes($Body.TrimEnd() + "`n"); Mode = '100644' })
    $Resources.Insert(0, [pscustomobject]@{ Name = 'source-manifest.json'; Bytes = $ManifestBytes; Mode = '100644' })
    $Resources.Insert(0, [pscustomobject]@{ Name = 'extension.yml'; Bytes = (ConvertTo-ExtensionJson $Extension); Mode = '100644' })
    $Resources.Add([pscustomobject]@{ Name = 'extension-build.json'; Bytes = (ConvertTo-ExtensionJson ([ordered]@{ Contract = 'skill-extension-pilot/1'; SourceArchiveSha256 = $ArchiveSha256; SourceCommit = $Manifest.SourceCommit; Root = $Root; SpecKitVersion = '1.2.3' })); Mode = '100644' })
    . (Join-Path $PSScriptRoot 'Invoke-Archive.ps1') -OutputDirectory $OutputDirectory
    try {
        if (-not [IO.Path]::IsPathFullyQualified($OutputDirectory) -or $OutputDirectory.Split('/') -contains '.' -or $OutputDirectory.Split('/') -contains '..') { throw 'Ambiguous output path.' }
        $Destination = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('/')
        $Parent = [IO.Path]::GetDirectoryName($Destination)
        $RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..')).TrimEnd('/')
        [void](Assert-ArchiveDirectory -Path $Parent -Excluded @($RepoRoot))
        if (Test-Path -LiteralPath $Destination) { throw 'Existing output.' }
        $Mkdir = (Get-Command mkdir -CommandType Application -TotalCount 1).Source
        & $Mkdir '-m' '700' '--' $Destination 2>$null
        if ($LASTEXITCODE) { throw 'Exclusive reservation failed.' }
    }
    catch { throw 'Output: Use a new absolute destination under an existing unlinked trusted parent outside the source checkout. Existing output is never overwritten.' }
    try {
        $Name = "$($Root.Id)-$($Root.Version).zip"
        $ZipPath = Join-Path $Destination $Name
        $Output = [IO.File]::Open($ZipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $Zip = [IO.Compression.ZipArchive]::new($Output, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($Resource in $Resources) {
                $Entry = $Zip.CreateEntry($Resource.Name, [IO.Compression.CompressionLevel]::NoCompression)
                $Entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $Entry.ExternalAttributes = [Convert]::ToInt32($Resource.Mode, 8) -shl 16
                $Stream = $Entry.Open()
                try { $Stream.Write($Resource.Bytes) }
                finally { $Stream.Dispose() }
            }
        }
        finally { $Zip.Dispose(); $Output.Flush($true); $Output.Dispose() }
        $Digest = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $Catalog = [ordered]@{
            schema_version = '1.0'
            extensions = @{ $Root.Id = [ordered]@{
                name = $Root.Id; description = $Description; version = $Root.Version
                download_url = [uri]::new($Uri, $Name).AbsoluteUri; sha256 = $Digest
                requires = $Extension.requires; provides = $Extension.provides
            } }
        }
        $CatalogPath = Join-Path $Destination 'catalog.json'
        $ChecksumPath = "$ZipPath.sha256"
        foreach ($File in @(@{ Path = $CatalogPath; Bytes = (ConvertTo-ExtensionJson $Catalog) }, @{ Path = $ChecksumPath; Bytes = [Text.Encoding]::UTF8.GetBytes("$Digest  $Name`n") })) {
            $Stream = [IO.File]::Open($File.Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $Stream.Write($File.Bytes); $Stream.Flush($true) }
            finally { $Stream.Dispose() }
        }
    }
    catch { throw "Output: Extension generation failed. Partial output retained at $Destination; inspect it deliberately. No success is reported." }
    return [pscustomobject]@{ RootId = $Root.Id; RootVersion = $Root.Version; Command = $Command; ArchivePath = $ZipPath; ArchiveSha256 = $Digest; CatalogPath = $CatalogPath; ChecksumPath = $ChecksumPath }
}
#endregion Functions

#region Main Execution
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-SkillExtension @PSBoundParameters | ConvertTo-Json -Depth 10
        exit 0
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}
#endregion Main Execution
