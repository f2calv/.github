#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Embeds reviewed non-secret UTF-8 text in one existing tracked ConfigMap key.
.DESCRIPTION
    Validates and prepares YAML in memory, preserving surrounding semantic values.
    Never prints payloads or passes them in process arguments or temporary files.
.PARAMETER SourceRoot
    Absolute source containment root, independent of this script's location.
.PARAMETER SourcePath
    Existing file contained by SourceRoot.
.PARAMETER TargetRoot
    Absolute target Git worktree root.
.PARAMETER TargetPath
    Existing tracked, clean manifest contained by TargetRoot.
.PARAMETER ConfigMapName
    Exact expected metadata name.
.PARAMETER ConfigMapNamespace
    Exact expected explicit metadata namespace.
.PARAMETER DataKey
    Existing string key under data.
.PARAMETER Format
    Explicit Json, Xml or Text format.
.PARAMETER XmlRoot
    Optional required XML local root name.
.PARAMETER LocalConfigPath
    Optional ignored, untracked PowerShell data file contained by SourceRoot.
.PARAMETER ReviewedNonSecret
    Acknowledges human review that the complete source contains no secrets.
.EXAMPLE
    ./Set-ConfigMapFromFile.ps1 -SourceRoot C:\work\example -LocalConfigPath sync.local.psd1 -ReviewedNonSecret -WhatIf
.NOTES
    Requires Git and Mike Farah yq v4. No deployment or repository publication.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourceRoot,
    [string]$SourcePath,
    [string]$TargetRoot,
    [string]$TargetPath,
    [string]$ConfigMapName,
    [string]$ConfigMapNamespace,
    [string]$DataKey,
    [string]$Format,
    [string]$XmlRoot,
    [string]$LocalConfigPath,
    [switch]$ReviewedNonSecret
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

#region In-memory process and file boundaries
function Invoke-ConfigMapProcess {
    [CmdletBinding()]
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [AllowEmptyString()][string]$InputText = ''
    )
    $Process = [Diagnostics.Process]::new()
    $Started = $false
    try {
        $Start = [Diagnostics.ProcessStartInfo]::new()
        $Start.FileName = $Executable
        $Start.UseShellExecute = $false
        $Start.CreateNoWindow = $true
        $Start.RedirectStandardInput = $true
        $Start.RedirectStandardOutput = $true
        $Start.RedirectStandardError = $true
        $Start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
        $Start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
        $Start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
        foreach ($Argument in $Arguments) { $Start.ArgumentList.Add($Argument) }
        $Process.StartInfo = $Start
        $null = $Process.Start()
        $Started = $true
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $InputTask = $Process.StandardInput.WriteAsync($InputText)
        if (-not $InputTask.Wait(30000)) { throw 'Input timeout.' }
        $Process.StandardInput.Close()
        if (-not $Process.WaitForExit(30000)) { throw 'Process timeout.' }
        $Output = $OutputTask.GetAwaiter().GetResult()
        $null = $ErrorTask.GetAwaiter().GetResult()
        return @{ ExitCode = $Process.ExitCode; Output = $Output }
    }
    catch {
        throw 'Local tool execution failed. Check installed tools and retry.'
    }
    finally {
        if ($Started -and -not $Process.HasExited) {
            $Process.Kill($true)
            $Process.WaitForExit()
        }
        $Process.Dispose()
    }
}

function Resolve-ConfigMapPath {
    [CmdletBinding()]
    param([string]$Root, [string]$Path)
    if (-not [IO.Path]::IsPathFullyQualified($Root)) { throw 'An absolute containment root is required.' }
    $Root = [IO.Path]::GetFullPath($Root)
    if (-not [IO.Directory]::Exists($Root)) { throw 'The containment root must exist.' }
    $Candidate = [IO.Path]::GetFullPath($Path, $Root)
    $Comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $Prefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $Candidate.StartsWith($Prefix, $Comparison)) { throw 'The file must be inside its configured root.' }
    $Current = $Candidate
    while ($Current) {
        $Item = Get-Item -LiteralPath $Current -Force
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $Item.LinkType) {
            throw 'Paths cannot traverse symbolic links or reparse points.'
        }
        $Current = [IO.Path]::GetDirectoryName($Current)
    }
    if (-not [IO.File]::Exists($Candidate) -or
        $Candidate.Substring([IO.Path]::GetPathRoot($Candidate).Length).Contains(':')) {
        throw 'An ordinary existing file is required.'
    }
    return $Candidate
}

function Read-ConfigMapBytes {
    [CmdletBinding()]
    param([string]$Path, [int]$Limit)
    $Stream = [IO.File]::OpenRead($Path)
    try {
        if ($Stream.Length -gt $Limit) { throw 'File exceeds the supported size limit.' }
        $Bytes = [byte[]]::new([int]$Stream.Length)
        # The Span overload can receive a copy through PowerShell's binder.
        $Stream.ReadExactly($Bytes, 0, $Bytes.Length)
        if ($Stream.ReadByte() -ne -1) { throw 'File changed while reading.' }
        return ,$Bytes
    }
    finally { $Stream.Dispose() }
}

function ConvertFrom-ConfigMapUtf8 {
    [CmdletBinding()]
    param([byte[]]$Bytes)
    try {
        $Text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
        if ($Text.StartsWith([string][char]0xFEFF, [StringComparison]::Ordinal)) { $Text = $Text.Substring(1) }
        return $Text
    }
    catch { throw 'File must contain valid UTF-8 text.' }
}

function ConvertTo-ConfigMapLf {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Assert-ConfigMapXml {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text, [string]$XmlRoot)
    $Options = [Xml.XmlReaderSettings]::new()
    $Options.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $Options.XmlResolver = $null
    $Options.MaxCharactersInDocument = 1MB
    $Reader = [Xml.XmlReader]::Create([IO.StringReader]::new($Text), $Options)
    try {
        while ($Reader.Read()) {
            if ($Reader.NodeType -eq [Xml.XmlNodeType]::XmlDeclaration) {
                $Encoding = $Reader.GetAttribute('encoding')
                if ($Encoding -and $Encoding -ine 'utf-8') { throw 'Encoding mismatch.' }
            }
            if ($Reader.NodeType -eq [Xml.XmlNodeType]::Element -and $Reader.Depth -eq 0 -and
                $XmlRoot -and $Reader.LocalName -cne $XmlRoot) { throw 'Root mismatch.' }
        }
    }
    finally { $Reader.Dispose() }
}

function Assert-ConfigMapSource {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text, [string]$Format, [string]$XmlRoot)
    try {
        switch -CaseSensitive ($Format) {
            'Json' {
                $Options = [Text.Json.JsonDocumentOptions]::new()
                $Options.AllowTrailingCommas = $true
                $Options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
                $Document = [Text.Json.JsonDocument]::Parse($Text, $Options)
                $Document.Dispose()
            }
            'Xml' {
                Assert-ConfigMapXml $Text $XmlRoot
            }
            'Text' { }
            default { throw 'Unknown format.' }
        }
    }
    catch { throw 'Source format validation failed. Check syntax, encoding and any required XML root locally.' }
}
#endregion

#region YAML and Git validation
function Invoke-ConfigMapYq {
    [CmdletBinding()]
    param([string]$Yq, [string[]]$Arguments, [AllowEmptyString()][string]$Text)
    $Result = Invoke-ConfigMapProcess -Executable $Yq -Arguments $Arguments -InputText $Text
    if ($Result.ExitCode -ne 0) { throw 'YAML processing failed. Check the manifest and yq version locally.' }
    return $Result.Output
}

function Read-ConfigMapDocument {
    [CmdletBinding()]
    param([string]$Yq, [string]$Text)
    # Refuse duplicates before YAML-to-JSON conversion can collapse them.
    $Duplicates = Invoke-ConfigMapYq $Yq @('eval-all', '-o=json', '-I=0',
        '[.. | select(tag == "!!map") | keys | group_by(.) | .[] | select(length > 1)] | length', '-') $Text
    if ($Duplicates.Trim() -cne '0') { throw 'Duplicate YAML keys are not supported.' }
    $Json = Invoke-ConfigMapYq $Yq @('eval-all', '-o=json', '-I=0', '[.]', '-') $Text
    try {
        $Documents = [Text.Json.Nodes.JsonNode]::Parse($Json)
        if ($Documents -isnot [Text.Json.Nodes.JsonArray] -or $Documents.Count -ne 1 -or
            $Documents[0] -isnot [Text.Json.Nodes.JsonObject]) { throw 'Document count or shape.' }
        return ,$Documents[0].DeepClone()
    }
    catch { throw 'Require exactly one YAML mapping document.' }
}

function Assert-ConfigMapIdentity {
    [CmdletBinding()]
    param([Text.Json.Nodes.JsonNode]$Document, [hashtable]$Settings)
    try {
        if ($Document['apiVersion'].GetValue[string]() -cne 'v1' -or
            $Document['kind'].GetValue[string]() -cne 'ConfigMap' -or
            $Document['metadata']['name'].GetValue[string]() -cne $Settings.ConfigMapName -or
            $Document['metadata']['namespace'].GetValue[string]() -cne $Settings.ConfigMapNamespace -or
            ($Document['immutable'] -and $Document['immutable'].GetValue[bool]())) { throw 'Identity.' }
        $Data = $Document['data']
        if ($Data -isnot [Text.Json.Nodes.JsonObject] -or -not $Data.ContainsKey($Settings.DataKey)) { throw 'Missing key.' }
        $Total = 0L
        foreach ($Entry in $Data) {
            $Total += [Text.Encoding]::UTF8.GetByteCount($Entry.Value.GetValue[string]())
        }
        if ($Document['binaryData']) {
            foreach ($Entry in $Document['binaryData']) {
                if ($Data.ContainsKey($Entry.Key)) { throw 'Overlapping keys.' }
                $Total += [Convert]::FromBase64String($Entry.Value.GetValue[string]()).Length
            }
        }
        if ($Total -gt 1MB) { throw 'Size.' }
    }
    catch { throw 'ConfigMap identity, string data, mutability or aggregate 1 MiB limit is invalid.' }
}

function Assert-ConfigMapGit {
    [CmdletBinding()]
    param([string]$Git, [string]$Root, [string]$Path)
    $Relative = [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
    $Top = Invoke-ConfigMapProcess $Git @('-C', $Root, 'rev-parse', '--show-toplevel')
    $Comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($Top.ExitCode -ne 0 -or -not [IO.Path]::GetFullPath($Top.Output.Trim()).Equals(
            [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar), $Comparison)) {
        throw 'TargetRoot must be the Git worktree root.'
    }
    $Tracked = Invoke-ConfigMapProcess $Git @('--literal-pathspecs', '-C', $Root, 'ls-files', '-v', '--', $Relative)
    $Stage = Invoke-ConfigMapProcess $Git @('--literal-pathspecs', '-C', $Root, 'ls-files', '--stage', '--', $Relative)
    $Status = Invoke-ConfigMapProcess $Git @('--literal-pathspecs', '-C', $Root, 'status', '--porcelain=v1', '--', $Relative)
    $Diff = Invoke-ConfigMapProcess $Git @('--literal-pathspecs', '-C', $Root, 'diff', '--quiet', '--no-ext-diff',
        '--no-textconv', 'HEAD', '--', $Relative)
    if ($Tracked.ExitCode -ne 0 -or $Tracked.Output -cnotmatch '^H [^\r\n]+\r?\n$' -or
        $Stage.ExitCode -ne 0 -or $Stage.Output -notmatch '^100(644|755) [a-f0-9]+ 0\t[^\r\n]+\r?\n$' -or
        $Status.ExitCode -ne 0 -or $Status.Output.Length -ne 0 -or $Diff.ExitCode -ne 0) {
        throw 'Target must be tracked and clean, without assume-unchanged or skip-worktree flags.'
    }
}

function Assert-ConfigMapCandidate {
    [CmdletBinding()]
    param([string]$Yq, [string]$Text, [Text.Json.Nodes.JsonNode]$Expected, [hashtable]$Settings,
        [AllowEmptyString()][string]$Source)
    $Actual = Read-ConfigMapDocument $Yq $Text
    Assert-ConfigMapIdentity $Actual $Settings
    if (-not [Text.Json.Nodes.JsonNode]::DeepEquals($Expected, $Actual) -or
        $Actual['data'][$Settings.DataKey].GetValue[string]() -cne $Source) {
        throw 'Candidate differs from the expected text or surrounding semantic values.'
    }
    Assert-ConfigMapSource ($Actual['data'][$Settings.DataKey].GetValue[string]()) $Settings.Format $Settings.XmlRoot
}
#endregion

#region Local settings and synchronization
function Read-ConfigMapLocalSettings {
    [CmdletBinding()]
    param([hashtable]$Explicit, [string]$Git, [string[]]$AllowedKeys)
    if (-not $Explicit.ContainsKey('LocalConfigPath')) { return @{} }
    $Local = Resolve-ConfigMapPath $Explicit.SourceRoot $Explicit.LocalConfigPath
    $Relative = [IO.Path]::GetRelativePath($Explicit.SourceRoot, $Local).Replace('\', '/')
    $Ignored = Invoke-ConfigMapProcess $Git @('-C', $Explicit.SourceRoot,
        'check-ignore', '--quiet', '--', $Relative)
    $Tracked = Invoke-ConfigMapProcess $Git @('--literal-pathspecs', '-C', $Explicit.SourceRoot,
        'ls-files', '--', $Relative)
    if ($Ignored.ExitCode -ne 0 -or $Tracked.ExitCode -ne 0 -or $Tracked.Output.Length -ne 0) {
        throw 'Local data must be gitignored and untracked.'
    }
    try { $LocalSettings = Import-PowerShellDataFile -LiteralPath $Local }
    catch { throw 'Local data could not be imported safely.' }
    foreach ($Key in $LocalSettings.Keys) {
        if ($Key -notin $AllowedKeys -or $LocalSettings[$Key] -isnot [string]) { throw 'Unsupported local data key or type.' }
    }
    return $LocalSettings
}

function Assert-ConfigMapSettings {
    [CmdletBinding()]
    param([hashtable]$Settings, [string[]]$RequiredKeys)
    foreach ($Key in $RequiredKeys) {
        if (-not $Settings.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Settings[$Key])) {
            throw 'A required source, target, identity or format setting is missing.'
        }
    }
    if ($Settings.Format -cnotin @('Json', 'Xml', 'Text') -or
        ($Settings.XmlRoot -and $Settings.Format -cne 'Xml') -or
        $Settings.DataKey -cnotmatch '^[A-Za-z0-9._-]{1,253}$') { throw 'Invalid format, XML root option or data key.' }
}

function Get-ConfigMapSettings {
    [CmdletBinding()]
    param([hashtable]$Explicit, [string]$Git)
    $Keys = @('SourcePath', 'TargetRoot', 'TargetPath', 'ConfigMapName', 'ConfigMapNamespace', 'DataKey', 'Format', 'XmlRoot')
    $Settings = @{ XmlRoot = '' }
    if (-not $Explicit.ContainsKey('SourceRoot')) { throw 'SourceRoot is required explicitly.' }
    $LocalSettings = Read-ConfigMapLocalSettings $Explicit $Git $Keys
    foreach ($Key in $LocalSettings.Keys) {
        $Settings[$Key] = $LocalSettings[$Key]
    }
    foreach ($Key in $Explicit.Keys) {
        if ($Key -notin ($Keys + @('SourceRoot', 'LocalConfigPath'))) { throw 'Unsupported explicit setting.' }
        if ($Explicit[$Key] -isnot [string]) { throw 'Settings must be strings.' }
        $Settings[$Key] = $Explicit[$Key]
    }
    Assert-ConfigMapSettings $Settings ($Keys | Where-Object { $_ -ne 'XmlRoot' })
    return $Settings
}

function Set-ConfigMapFromFile {
    [CmdletBinding(SupportsShouldProcess)]
    param([hashtable]$Settings, [switch]$ReviewedNonSecret)
    if (-not $ReviewedNonSecret) { throw 'Explicit complete-source non-secret review is required.' }
    $Git = (Get-Command git -CommandType Application -TotalCount 1 -ErrorAction Stop).Source
    $Yq = (Get-Command yq -CommandType Application -TotalCount 1 -ErrorAction Stop).Source
    $Version = Invoke-ConfigMapProcess $Yq @('--version')
    if ($Version.ExitCode -ne 0 -or $Version.Output -notmatch 'github\.com/mikefarah/yq/.*version v4\.') {
        throw 'Mike Farah yq v4 is required.'
    }
    $Settings = Get-ConfigMapSettings $Settings $Git
    $SourcePath = Resolve-ConfigMapPath $Settings.SourceRoot $Settings.SourcePath
    $TargetPath = Resolve-ConfigMapPath $Settings.TargetRoot $Settings.TargetPath
    if ($SourcePath -eq $TargetPath) { throw 'Source and target must be different files.' }
    Assert-ConfigMapGit $Git $Settings.TargetRoot $TargetPath
    $Source = ConvertTo-ConfigMapLf (ConvertFrom-ConfigMapUtf8 (Read-ConfigMapBytes $SourcePath 1MB))
    Assert-ConfigMapSource $Source $Settings.Format $Settings.XmlRoot
    $Original = Read-ConfigMapBytes $TargetPath 8MB
    $Document = Read-ConfigMapDocument $Yq (ConvertFrom-ConfigMapUtf8 $Original)
    Assert-ConfigMapIdentity $Document $Settings
    if ((ConvertTo-ConfigMapLf ($Document['data'][$Settings.DataKey].GetValue[string]())) -ceq $Source) {
        return 'Unchanged'
    }
    $Expected = $Document.DeepClone()
    $Expected['data'][$Settings.DataKey] = [Text.Json.Nodes.JsonValue]::Create([string]$Source)
    Assert-ConfigMapIdentity $Expected $Settings
    $Envelope = @{ manifest = $Document; key = $Settings.DataKey; content = $Source }
    # Serialize JsonNode separately; PowerShell's serializer otherwise enumerates its implementation.
    $InputJson = '{"manifest":' + $Document.ToJsonString() + ',"key":' +
        (ConvertTo-Json $Envelope.key -Compress) + ',"content":' + (ConvertTo-Json $Envelope.content -Compress) + '}'
    $Candidate = Invoke-ConfigMapYq $Yq @('eval', '-p=json', '-o=yaml',
        '. as $input | .manifest | .data[$input.key] = $input.content | .data[$input.key] style="literal"', '-') $InputJson
    Assert-ConfigMapCandidate $Yq $Candidate $Expected $Settings $Source
    if (-not $PSCmdlet.ShouldProcess('the configured tracked ConfigMap key', 'Replace complete reviewed file text')) {
        return 'Validated'
    }
    $null = Resolve-ConfigMapPath $Settings.SourceRoot $Settings.SourcePath
    $null = Resolve-ConfigMapPath $Settings.TargetRoot $Settings.TargetPath
    Assert-ConfigMapGit $Git $Settings.TargetRoot $TargetPath
    $Current = Read-ConfigMapBytes $TargetPath 8MB
    if (-not [Linq.Enumerable]::SequenceEqual[byte]($Original, $Current) -or
        (ConvertTo-ConfigMapLf (ConvertFrom-ConfigMapUtf8 (Read-ConfigMapBytes $SourcePath 1MB))) -cne $Source) {
        throw 'Source or target changed during preparation; retry after review.'
    }
    try {
        [IO.File]::WriteAllText($TargetPath, $Candidate, [Text.UTF8Encoding]::new($false))
        $Written = ConvertFrom-ConfigMapUtf8 (Read-ConfigMapBytes $TargetPath 8MB)
        if ($Written -cne $Candidate) { throw 'Written bytes differ.' }
        Assert-ConfigMapCandidate $Yq $Written $Expected $Settings $Source
    }
    catch {
        try { [IO.File]::WriteAllBytes($TargetPath, $Original) }
        catch { throw 'Write verification and rollback failed. Stop and recover the target locally before retrying.' }
        throw 'Write verification failed; original target bytes restored.'
    }
    return 'Updated'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Settings = @{}
        foreach ($Key in $PSBoundParameters.Keys) {
            if ($Key -in @('SourceRoot', 'SourcePath', 'TargetRoot', 'TargetPath', 'ConfigMapName',
                    'ConfigMapNamespace', 'DataKey', 'Format', 'XmlRoot', 'LocalConfigPath')) {
                $Settings[$Key] = $PSBoundParameters[$Key]
            }
        }
        Set-ConfigMapFromFile -Settings $Settings -ReviewedNonSecret:$ReviewedNonSecret -WhatIf:$WhatIfPreference
        exit 0
    }
    catch {
        Write-Error 'File-to-ConfigMap synchronization failed. Check review, settings, paths, Git state, source syntax and tool versions locally; no payload diagnostics are emitted.' -ErrorAction Continue
        exit 1
    }
}
#endregion
