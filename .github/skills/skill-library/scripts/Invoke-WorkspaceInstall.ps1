#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Preview or explicitly apply a bounded root and selected optional extensions in a workspace.
.DESCRIPTION
Bind one committed root to explicit local catalogs and artifacts. Preview is consumer-read-only.
Apply recomputes approval, records durable intent, delegates to Spec Kit and verifies exact results.
Explicit optional keys select separate required-only artifacts. At most sixteen roots are allowed.
Provisioning, downloads, adoption and rollback are not supported.
.PARAMETER RepoRoot
Absolute existing source repository root.
.PARAMETER SourceRevision
Locally available source revision, defaulting to HEAD.
.PARAMETER SkillName
One native skill folder selector.
.PARAMETER OptionalSelection
Explicit reachable component-id/selectionKey choices; duplicates and inactive keys are invalid.
.PARAMETER WorkspacePath
Absolute existing initialized Copilot skills-mode consumer outside the source.
.PARAMETER CatalogPath
Absolute existing generated local catalog paths.
.PARAMETER ArtifactDirectory
Absolute existing directories containing selected prebuilt extension ZIPs.
.PARAMETER PythonPath
Absolute existing interpreter with PyYAML 6.0.3 and Spec Kit CLI 1.2.3.
.PARAMETER PackageIndexPath
Explicit existing bundled library index; selects packaged evidence instead of a source repository.
.PARAMETER PackageVersion
Exact packaged root version; omitted resolves the index's advertised current release during preview.
.PARAMETER LibraryRequest
Read one bounded typed packaged-operation JSON request from standard input; requires Json output.
.PARAMETER Apply
Explicitly install the selected roots in order after a fresh ready preview and matching approval.
.PARAMETER ReviewedFingerprint
Exact lowercase fingerprint of the reviewed ready preview; rejected on preview.
.PARAMETER Json
Render the script result as one JSON document. The function always returns an object.
.EXAMPLE
./Invoke-WorkspaceInstall.ps1 -RepoRoot /workspace/source -SkillName example -WorkspacePath /workspace/consumer -CatalogPath /workspace/artifacts/catalog.json -ArtifactDirectory /workspace/artifacts -PythonPath /workspace/tools/bin/python -Json
.NOTES
Linux and stable trusted local inputs only. Selected apply is synthetically validated; real-consumer,
interruption and editor gates require separate approval and validation. Partial state is retained.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot, [string]$SourceRevision = 'HEAD', [string]$SkillName,
    [string[]]$OptionalSelection = @(), [string]$WorkspacePath, [string[]]$CatalogPath = @(),
    [string[]]$ArtifactDirectory = @(), [string]$PythonPath, [switch]$Apply,
    [string]$ReviewedFingerprint, [switch]$Json, [string]$PackageIndexPath, [string]$PackageVersion,
    [switch]$LibraryRequest
)

#region Functions
function New-WorkspaceConflict {
    param(
        [ValidateSet('Selection', 'Prerequisite', 'Catalog', 'Artifact', 'Workspace', 'Ownership', 'CommandConflict', 'OperationState', 'ApprovalMismatch', 'RuntimeFailure', 'VerificationFailure')]
        [string]$Code,
        [string]$Scope, [string]$Explanation, [object]$Observed = $null, [object]$Expected = $null
    )
    [pscustomobject]@{ Code = $Code; Scope = $Scope; Explanation = $Explanation; Observed = $Observed; Expected = $Expected }
}

function New-WorkspacePreview {
    [pscustomobject]@{
        Contract = 'skill-workspace-install/1'; Mode = 'preview'; Ready = $false; Blockers = @()
        Selection = $null; OptionalOffers = @(); Extensions = @(); Overlaps = @()
        ConsumerSnapshot = $null; IntendedWrites = @(); Fingerprint = $null
    }
}

function New-WorkspaceApplyResult {
    param([string]$ReviewedFingerprint, [object[]]$Blockers = @())
    [pscustomobject]@{
        Contract = 'skill-workspace-install/1'; Mode = 'apply'; State = 'Blocked'
        ReviewedFingerprint = $ReviewedFingerprint; OperationPath = $null
        CompletedExtensions = @(); FailedExtensions = @(); UnknownExtensions = @(); PendingExtensions = @()
        ObservedPaths = @(); Blockers = @($Blockers); RecoveryLocations = @()
        MutationBegan = $false; LastDurableStep = $null
    }
}

function Get-WorkspaceExitCode {
    param([object]$Result)
    if ($Result.Mode -ceq 'preview') { if ($Result.Ready -and $Result.Blockers.Count -eq 0 -and $Result.Fingerprint) { return 0 }; return 2 }
    if ($Result.State -ceq 'Completed' -and $Result.Blockers.Count -eq 0 -and
        $Result.UnknownExtensions.Count -eq 0 -and $Result.FailedExtensions.Count -eq 0 -and
        $Result.PendingExtensions.Count -eq 0 -and $Result.CompletedExtensions.Count -gt 0 -and $Result.LastDurableStep -ceq 'Completed') { return 0 }
    if ($Result.State -ceq 'UnexpectedFailure') { return 4 }
    if ($Result.MutationBegan -or $Result.OperationPath) { return 3 }
    return 2
}

function Assert-WorkspaceInputPath {
    param([string]$Path, [switch]$Directory, [switch]$Executable)
    if (-not [IO.Path]::IsPathFullyQualified($Path) -or $Path.Contains('\') -or
        @($Path.Substring(1).Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) {
        throw 'Use an unambiguous absolute local path.'
    }
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($Directory -and -not $Item.PSIsContainer) { throw 'Supply an existing regular directory.' }
    if (-not $Directory -and $Item.PSIsContainer) { throw 'Supply an existing regular file.' }
    while ($null -ne $Item) {
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and -not ($Executable -and $Item.FullName -ceq $Path -and -not $Item.PSIsContainer)) {
            throw 'Linked inputs or ancestors are not supported.'
        }
        $Item = if ($Item -is [IO.FileInfo]) { $Item.Directory } else { $Item.Parent }
    }
}

function Invoke-WorkspaceBridge {
    param([string]$PythonPath, [hashtable]$Request, [string]$ScratchPath)
    . (Join-Path $PSScriptRoot 'Git-Process.ps1')
    $Request.Contract = 'skill-workspace-install/1'
    $Installing = $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply'
    $Environment = @{}
    if ($Installing) {
        Assert-WorkspaceInputPath -Path $ScratchPath -Directory
        if ([IO.File]::GetUnixFileMode($ScratchPath) -ne [IO.UnixFileMode]448) { throw 'Private scratch mode changed.' }
        $Environment.TMPDIR = $ScratchPath
    }
    else { $Request.Mode = 'inspect' }
    $Process = Invoke-LibraryProcess -Executable $PythonPath -Arguments @('-I', '-B', (Join-Path $PSScriptRoot 'Invoke-SpecKitInstall.py')) -Environment $Environment -InputBytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Request -Depth 100 -Compress)))
    if ($Process.ExitCode -notin @(0, 2, 3) -or $Process.Error) { throw 'Isolated bridge did not return a clean response; preserve operation evidence.' }
    $Response = [Text.UTF8Encoding]::new($false, $true).GetString($Process.Bytes) | ConvertFrom-Json -Depth 100
    $ExpectedStatus = if ($Installing) { if ($Process.ExitCode -eq 0) { 'Applied' } elseif ($Process.ExitCode -eq 3) { 'Failed' } else { 'Blocked' } } else { if ($Process.ExitCode -eq 0) { 'Inspected' } else { 'Blocked' } }
    if ($Response.Contract -cne 'skill-workspace-install/1' -or $Response.Status -cne $ExpectedStatus -or
        (-not $Installing -and $Process.ExitCode -eq 3)) { throw 'Bridge protocol mismatch; preserve operation evidence.' }
    return $Response
}

function Get-WorkspaceCommittedSelection {
    param([hashtable]$Inputs)
    . (Join-Path $PSScriptRoot 'Invoke-InventoryPreview.ps1')
    Get-SkillCommittedSelection @Inputs
}

function Get-WorkspacePackagedSelection {
    param([string]$PackageIndexPath, [string]$ArtifactDirectory, [string]$SkillName, [string]$PackageVersion, [string[]]$OptionalSelection, [string]$PythonPath)
    . (Join-Path $PSScriptRoot 'Git-Process.ps1')
    $Arguments = @('-I', '-B', (Join-Path $PSScriptRoot 'Invoke-Library.py'), '--catalog', $PackageIndexPath, '--artifacts', $ArtifactDirectory, '--package-selection', '--', 'install', $SkillName)
    if ($PackageVersion) { $Arguments += @('--version', $PackageVersion) }
    foreach ($Key in $OptionalSelection) { $Arguments += @('--optional', $Key) }
    $Process = Invoke-LibraryProcess -Executable $PythonPath -Arguments $Arguments
    if ($Process.ExitCode -ne 0 -or $Process.Error) { throw 'Packaged selection did not return a clean verified response.' }
    $Selection = [Text.UTF8Encoding]::new($false, $true).GetString($Process.Bytes) | ConvertFrom-Json -Depth 100
    if ($Selection.SourceKind -cne 'packaged') { throw 'Packaged selection protocol mismatch.' }
    Assert-WorkspacePackagedSelection -Selection $Selection
    return $Selection
}

function Assert-WorkspacePackagedSelection {
    param([object]$Selection)
    & {
        param($PackagedSelection, $Schema)
        . (Join-Path $PSScriptRoot 'Invoke-Validation.ps1')
        $Catalog = @{}
        foreach ($Component in $PackagedSelection.ComponentMetadata) {
            $Json = $Component.Metadata | ConvertTo-Json -Depth 64 -Compress
            if (-not (Test-Json -Json $Json -SchemaFile $Schema -ErrorAction SilentlyContinue)) { throw 'Packaged metadata schema validation failed.' }
            $Record = $Json | ConvertFrom-Json -AsHashtable -Depth 64
            foreach ($Collection in @('required', 'optional')) {
                if (-not $Record.ContainsKey($Collection)) { $Record[$Collection] = @() }
            }
            $Catalog[$Record.id] = $Record
        }
        $Available = $PackagedSelection.AvailableVersions | ConvertTo-Json -Depth 64 -Compress | ConvertFrom-Json -AsHashtable -Depth 64
        $Graph = Resolve-SkillGraph -Catalog $Catalog -RootId @($PackagedSelection.Root.Id) -OptionalSelection @($PackagedSelection.OptionalSelection) -AvailableVersions $Available
        if (@(Compare-Object @($Graph.SelectedIds | Sort-Object) @($Catalog.Keys | Sort-Object) -CaseSensitive).Count) { throw 'Packaged active closure does not match verified members.' }
        foreach ($Inventory in $PackagedSelection.RequiredInventories) {
            $Root = $PackagedSelection.ExtensionRoots[$Inventory.Position]
            $Required = Resolve-SkillGraph -Catalog $Catalog -RootId @($Root.Id) -AvailableVersions $Available
            if (@(Compare-Object @($Required.SelectedIds | Sort-Object) @($Inventory.Inventory.Components.Id | Sort-Object) -CaseSensitive).Count) { throw 'Packaged required-only closure does not match its manifest.' }
        }
    } $Selection (Join-Path $PSScriptRoot '../skill-metadata.schema.json')
}

function Get-WorkspaceConsumerSnapshot {
    param([string]$RepoRoot, [string]$WorkspacePath, [string]$PythonPath, [string]$RootId = '', [string[]]$RootIds = @(), [object[]]$IntendedWrites = @(), [string]$SourceKind = 'committed')
    Invoke-WorkspaceBridge -PythonPath $PythonPath -Request @{ Action = 'probe'; RepoRoot = $RepoRoot; WorkspacePath = $WorkspacePath; RootId = $RootId; RootIds = $RootIds; AdditionalPaths = @($IntendedWrites | ForEach-Object Path); SourceKind = $SourceKind }
}

function Get-WorkspaceIntendedWrites {
    param([object]$Extension, [int]$Position = 0)
    $Writes = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $Files = @(
        foreach ($Member in $Extension.Members) { [pscustomobject]@{ Path = ".specify/extensions/$($Extension.RootId)/$($Member.MemberPath)"; Effect = 'create-payload'; Mode = $Member.Mode; Sha256 = $Member.Sha256 } }
        [pscustomobject]@{ Path = '.specify/extensions/.registry'; Effect = 'register-extension'; Mode = 'preserve-or-0644'; Sha256 = $null }
        [pscustomobject]@{ Path = '.specify/extensions.yml'; Effect = 'add-installed-extension-preserve-empty-hooks'; Mode = 'preserve-or-0644'; Sha256 = $null }
        [pscustomobject]@{ Path = '.specify/skill-library-install/owner.json'; Effect = 'create-if-absent-owner'; Mode = '0600'; Sha256 = $null }
        [pscustomobject]@{ Path = '.specify/skill-library-install/lock'; Effect = 'exclusive-lock'; Mode = '0600'; Sha256 = $null }
        [pscustomobject]@{ Path = '.specify/skill-library-install/operations/{operation}/operation.json'; Effect = 'durable-receipt'; Mode = '0600'; Sha256 = $null }
        [pscustomobject]@{ Path = '.specify/skill-library-install/operations/{operation}/operation.json.{temporary}.tmp'; Effect = 'private-evidence-temporary'; Mode = '0600'; Sha256 = $null }
        [pscustomobject]@{ Path = '.specify/skill-library-install/operations/{operation}/scratch'; Effect = 'private-extraction-subtree'; Mode = '0700'; Sha256 = $null }
    )
    foreach ($File in $Files) {
        $Record = [pscustomobject]@{ Path = $File.Path; Position = $Position; Effect = $File.Effect; Mode = $File.Mode; Sha256 = $File.Sha256 }
        $Writes[$File.Path] = $Record
        $Parent = [IO.Path]::GetDirectoryName($File.Path)
        while ($Parent) {
            if (-not $Writes.ContainsKey($Parent)) {
                $Writes[$Parent] = [pscustomobject]@{
                    Path = $Parent; Position = $Position; Effect = 'create-parent-if-absent'
                    Mode = $(if ($Parent.StartsWith('.specify/skill-library-install', [StringComparison]::Ordinal) -or $Parent -ceq ".specify/extensions/$($Extension.RootId)") { '0700' } else { 'preserve-or-0755' }); Sha256 = $null
                }
            }
            $Parent = [IO.Path]::GetDirectoryName($Parent)
        }
    }
    return ,@($Writes.Values)
}

function Get-WorkspaceFingerprint {
    param([string]$PythonPath, [object]$Projection)
    $Response = Invoke-WorkspaceBridge -PythonPath $PythonPath -Request @{ Action = 'fingerprint'; Projection = $Projection }
    if ($Response.Status -cne 'Inspected' -or $Response.Result.Fingerprint -cnotmatch '^[0-9a-f]{64}$') { throw 'Canonical approval encoding failed.' }
    return $Response.Result.Fingerprint
}

function Assert-WorkspaceApplyContext {
    param([object]$Context)
    if ($Context.Mode -cne 'apply' -or -not $Context.ApprovedInputs.Ready -or
        $Context.OperationId -cnotmatch '^[0-9a-f]{64}$' -or
        $Context.OperationId -cne $Context.ApprovedInputs.Fingerprint) { throw 'A revalidated private apply context is required.' }
    Assert-WorkspaceInputPath -Path $Context.WorkspacePath -Directory
}

function Write-WorkspaceOwnedFile {
    param([object]$Context, [string]$Path, [byte[]]$Bytes, [switch]$Replace, [string]$PreviousSha256)
    Assert-WorkspaceApplyContext $Context
    $Namespace = Join-Path $Context.WorkspacePath '.specify/skill-library-install'
    if (-not $Path.StartsWith("$Namespace/", [StringComparison]::Ordinal)) { throw 'Evidence must stay inside the owned namespace.' }
    Assert-WorkspaceInputPath -Path ([IO.Path]::GetDirectoryName($Path)) -Directory
    $IdentityRequest = @{ Action = 'evidence-identity'; WorkspacePath = $Context.WorkspacePath; Path = $Path }
    if ($Replace) {
        Assert-WorkspaceInputPath $Path
        $Identity = Invoke-WorkspaceBridge -PythonPath $Context.PythonPath -Request $IdentityRequest
        if ($Identity.Status -cne 'Inspected' -or -not $Context.OwnedFiles.ContainsKey($Path) -or
            (ConvertTo-Json -InputObject $Identity.Result -Compress) -cne $Context.OwnedFiles[$Path]) { throw 'Evidence is not the unchanged owned file; preserve it.' }
        if ($PreviousSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $PreviousSha256 -or
            [IO.File]::GetUnixFileMode($Path) -ne [IO.UnixFileMode]384) { throw 'Existing evidence identity changed; preserve it for inspection.' }
    }
    $Temporary = if ($Replace) { "$Path.$([guid]::NewGuid().ToString('N')).tmp" } else { $Path }
    $Options = [IO.FileStreamOptions]::new()
    $Options.Mode = [IO.FileMode]::CreateNew
    $Options.Access = [IO.FileAccess]::Write
    $Options.Share = [IO.FileShare]::None
    $Options.UnixCreateMode = [IO.UnixFileMode]384
    $Stream = [IO.FileStream]::new($Temporary, $Options)
    $Context.MutationBegan = $true
    $Context.CreatedPaths.Add($Temporary)
    try { $Stream.Write($Bytes); $Stream.Flush($true) }
    finally { $Stream.Dispose() }
    if ($Replace) {
        Assert-WorkspaceInputPath $Path
        $Identity = Invoke-WorkspaceBridge -PythonPath $Context.PythonPath -Request $IdentityRequest
        if ($Identity.Status -cne 'Inspected' -or
            (ConvertTo-Json -InputObject $Identity.Result -Compress) -cne $Context.OwnedFiles[$Path]) { throw 'Evidence changed before replacement; retain both copies.' }
        [IO.File]::Move($Temporary, $Path, $true)
    }
    $Identity = Invoke-WorkspaceBridge -PythonPath $Context.PythonPath -Request $IdentityRequest
    if ($Identity.Status -cne 'Inspected' -or $Identity.Result.Mode -cne '0600') { throw 'Cannot record private owned evidence; retain it for inspection.' }
    $Context.OwnedFiles[$Path] = ConvertTo-Json -InputObject $Identity.Result -Compress
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function New-WorkspaceOperationEvidence {
    param([object]$Context)
    Assert-WorkspaceApplyContext $Context
    $SourceKind = if ($Context.PSObject.Properties.Name -contains 'SourceKind') { $Context.SourceKind } else { 'committed' }
    $Probe = Get-WorkspaceConsumerSnapshot -RepoRoot $Context.RepoRoot -WorkspacePath $Context.WorkspacePath -PythonPath $Context.PythonPath -SourceKind $SourceKind
    if ($Probe.Status -cne 'Inspected') { throw 'Unresolved or unsafe workspace state blocks reservation.' }
    if ($Context.PSObject.Properties.Name -notcontains 'OwnedFiles') {
        $Context | Add-Member -NotePropertyName OwnedFiles -NotePropertyValue ([Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal))
    }
    $Context | Add-Member -NotePropertyName MutationBegan -NotePropertyValue $false
    $Context | Add-Member -NotePropertyName CreatedPaths -NotePropertyValue ([Collections.Generic.List[string]]::new())
    . (Join-Path $PSScriptRoot 'Git-Process.ps1')
    $Mkdir = (Get-Command mkdir -CommandType Application -TotalCount 1).Source
    $Namespace = Join-Path $Context.WorkspacePath '.specify/skill-library-install'
    if (-not [IO.Directory]::Exists($Namespace)) {
        $Reservation = Invoke-LibraryProcess -Executable $Mkdir -Arguments @('-m', '700', '--', $Namespace)
        if ($Reservation.ExitCode -ne 0) { throw 'Exclusive namespace creation failed; preserve existing state.' }
        $Context.MutationBegan = $true
        $Context.CreatedPaths.Add($Namespace)
        $Marker = [Text.Encoding]::UTF8.GetBytes('{"Contract":"skill-workspace-install/1","Kind":"operation-namespace"}')
        [void](Write-WorkspaceOwnedFile -Context $Context -Path (Join-Path $Namespace 'owner.json') -Bytes $Marker)
    }
    $LockBytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ Contract = 'skill-workspace-install/1'; OperationId = $Context.OperationId } -Compress))
    [void](Write-WorkspaceOwnedFile -Context $Context -Path (Join-Path $Namespace 'lock') -Bytes $LockBytes)
    $Operations = Join-Path $Namespace 'operations'
    $OperationPath = Join-Path $Operations $Context.OperationId
    $Context | Add-Member -NotePropertyName OperationPath -NotePropertyValue $OperationPath
    $Directories = @($OperationPath, (Join-Path $OperationPath 'scratch'))
    if ([IO.Directory]::Exists($Operations)) {
        Assert-WorkspaceInputPath -Path $Operations -Directory
        if ([IO.File]::GetUnixFileMode($Operations) -ne [IO.UnixFileMode]448) { throw 'Private operations directory mode changed.' }
    }
    else { $Directories = @($Operations) + $Directories }
    foreach ($Directory in $Directories) {
        $Reservation = Invoke-LibraryProcess -Executable $Mkdir -Arguments @('-m', '700', '--', $Directory)
        if ($Reservation.ExitCode -ne 0) { throw 'Exclusive operation directory creation failed; preserve existing state.' }
        $Context.MutationBegan = $true
        $Context.CreatedPaths.Add($Directory)
    }
    return $OperationPath
}

function Write-WorkspaceOperationReceipt {
    param(
        [object]$Context, [string]$OperationPath,
        [ValidateSet('Prepared', 'Running', 'Completed', 'Failed', 'Cancelled', 'Unknown')][string]$State,
        [object[]]$Extensions, [object[]]$ObservedPaths = @(), [string[]]$RecoveryLocations = @(),
        [string]$LastDurableStep, [string]$PreviousSha256
    )
    Assert-WorkspaceApplyContext $Context
    $ExpectedPath = Join-Path $Context.WorkspacePath ".specify/skill-library-install/operations/$($Context.OperationId)"
    if ($OperationPath -cne $ExpectedPath -or -not $LastDurableStep -or $Extensions.Count -eq 0 -or
        @($Extensions | Where-Object { $_.State -notin @('Pending', 'Attempting', 'Verified', 'Failed', 'Unknown') }).Count -gt 0) { throw 'Invalid operation receipt.' }
    if ($State -ceq 'Completed' -and (@($Extensions | Where-Object State -CNE 'Verified').Count -or $LastDurableStep -cne 'Completed')) { throw 'Completion requires verified extensions and durable evidence.' }
    $Receipt = [ordered]@{
        Contract = 'skill-workspace-install/1'; OperationId = $Context.OperationId
        ReviewedFingerprint = $Context.OperationId; ApprovedInputs = $Context.ApprovedInputs
        State = $State; Extensions = @($Extensions); IntendedPaths = @($Context.ApprovedInputs.IntendedWrites)
        ObservedPaths = @($ObservedPaths); RecoveryLocations = @($RecoveryLocations); LastDurableStep = $LastDurableStep
    }
    $Bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Receipt -Depth 100 -Compress))
    Write-WorkspaceOwnedFile -Context $Context -Path (Join-Path $OperationPath 'operation.json') -Bytes $Bytes -Replace:([bool]$PreviousSha256) -PreviousSha256 $PreviousSha256
}

function Remove-WorkspaceOperationLock {
    param([object]$Context)
    Assert-WorkspaceApplyContext $Context
    $Path = Join-Path $Context.WorkspacePath '.specify/skill-library-install/lock'
    $Response = Invoke-WorkspaceBridge -PythonPath $Context.PythonPath -Request @{ Action = 'evidence-identity'; WorkspacePath = $Context.WorkspacePath; Path = $Path }
    if ($Response.Status -cne 'Inspected' -or -not $Context.OwnedFiles.ContainsKey($Path) -or
        (ConvertTo-Json -InputObject $Response.Result -Compress) -cne $Context.OwnedFiles[$Path]) { throw 'Lock identity changed; preserve it for inspection.' }
    Assert-WorkspaceInputPath $Path
    [IO.File]::Delete($Path)
}

function Invoke-WorkspaceOrderedApply {
    param(
        [object]$Context, [object]$Result, [object]$State,
        [scriptblock]$ValidateStep, [scriptblock]$InstallStep,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )
    try {
        for ($Index = 0; $Index -lt $State.Extensions.Count; $Index++) {
            $CancellationToken.ThrowIfCancellationRequested()
            if ($State.Extensions[$Index].State -cne 'Pending' -or
                @($State.Extensions | Select-Object -First $Index | Where-Object State -CNE 'Verified').Count) { throw 'Invalid ordered apply state.' }
            $Check = & $ValidateStep $Index $State.Extensions $Result.ObservedPaths
            if ($Check.Status -cne 'Inspected') { $Result.Blockers = @($Check.Blockers); throw 'Reserved state did not match approval.' }
            $Result.ObservedPaths = @($Check.Result.Paths)
            $CancellationToken.ThrowIfCancellationRequested()
            $Attempting = @($State.Extensions | ForEach-Object { [pscustomobject]@{ RootId = $_.RootId; State = $_.State } })
            $Attempting[$Index].State = 'Attempting'
            $State.ReceiptHash = Write-WorkspaceOperationReceipt -Context $Context -OperationPath $Context.OperationPath -State Running -Extensions $Attempting -LastDurableStep Attempting -ObservedPaths $Result.ObservedPaths -RecoveryLocations $Result.RecoveryLocations -PreviousSha256 $State.ReceiptHash
            $State.Extensions[$Index].State = 'Attempting'
            $Result.LastDurableStep = 'Attempting'
            $CancellationToken.ThrowIfCancellationRequested()
            $Response = & $InstallStep $Index
            if ($Response.Result) {
                $Result.ObservedPaths = @($Response.Result.ObservedPaths)
                $Result.Blockers = @($Response.Blockers)
                $State.Cancelled = $Response.Result.PSObject.Properties.Name -contains 'Cancelled' -and $Response.Result.Cancelled -eq $true
            }
            if ($Response.Status -cne 'Applied' -or -not $Response.Result -or $Response.Result.Outcome -cne 'Verified' -or
                -not $Response.Result.Called -or $Result.Blockers.Count -or $Result.ObservedPaths.Count -eq 0) {
                $State.Extensions[$Index].State = if ($Response.Result -and $Response.Result.Outcome -ceq 'Failed') { 'Failed' } else { 'Unknown' }
                throw 'Runtime outcome was not verified.'
            }
            $State.Extensions[$Index].State = 'Verified'
            $State.ReceiptHash = Write-WorkspaceOperationReceipt -Context $Context -OperationPath $Context.OperationPath -State Running -Extensions $State.Extensions -LastDurableStep Verified -ObservedPaths $Result.ObservedPaths -RecoveryLocations $Result.RecoveryLocations -PreviousSha256 $State.ReceiptHash
            $Result.LastDurableStep = 'Verified'
            $CancellationToken.ThrowIfCancellationRequested()
        }
    }
    catch {
        if ($CancellationToken.IsCancellationRequested -or $_.Exception -is [OperationCanceledException]) { $State.Cancelled = $true }
        foreach ($Entry in $State.Extensions) { if ($Entry.State -ceq 'Attempting') { $Entry.State = 'Unknown' } }
        throw
    }
}

function Invoke-WorkspaceRootApply {
    param([object]$Approved, [string]$PythonPath)
    $Result = New-WorkspaceApplyResult -ReviewedFingerprint $Approved.Fingerprint
    $Context = [pscustomobject]@{
        Mode = 'apply'; ApprovedInputs = $Approved; OperationId = $Approved.Fingerprint
        WorkspacePath = $Approved.ConsumerSnapshot.WorkspacePath; RepoRoot = $Approved.Selection.SourceRoot; PythonPath = $PythonPath
        SourceKind = $(if ($Approved.Selection.PSObject.Properties.Name -contains 'SourceKind') { $Approved.Selection.SourceKind } else { 'committed' })
    }
    $Extensions = @($Approved.Extensions | ForEach-Object { [pscustomobject]@{ RootId = $_.RootId; State = 'Pending' } })
    $State = [pscustomobject]@{ Extensions = $Extensions; ReceiptHash = $null; Cancelled = $false }
    $OperationPath = Join-Path $Context.WorkspacePath ".specify/skill-library-install/operations/$($Context.OperationId)"
    $Result.PendingExtensions = @($Extensions)
    try {
        $OperationPath = New-WorkspaceOperationEvidence $Context
        $Result.OperationPath = $OperationPath
        $Result.MutationBegan = $true
        $Result.RecoveryLocations = @($OperationPath, (Join-Path $OperationPath 'scratch'))
        $State.ReceiptHash = Write-WorkspaceOperationReceipt -Context $Context -OperationPath $OperationPath -State Prepared -Extensions $Extensions -LastDurableStep Prepared -RecoveryLocations $Result.RecoveryLocations
        $Result.LastDurableStep = 'Prepared'
        $Request = @{
            Action = 'validate-reservation'; RepoRoot = $Context.RepoRoot; WorkspacePath = $Context.WorkspacePath
            OperationPath = $OperationPath; ApprovedInputs = $Approved; OwnedFiles = $Context.OwnedFiles; ExpectedStep = 'Prepared'
            SourceKind = $Context.SourceKind
        }
        $ValidateStep = {
            param($Index, $Entries, $Observed)
            $Request.StepIndex = $Index
            $Request.ExpectedStep = if ($Index -eq 0) { 'Prepared' } else { 'Verified' }
            Invoke-WorkspaceBridge -PythonPath $PythonPath -Request $Request
        }
        $InstallStep = {
            param($Index)
            $InstallRequest = @{} + $Request
            $InstallRequest.Mode = 'apply'
            $InstallRequest.Action = 'install-root'
            $InstallRequest.Contract = 'skill-workspace-install/1'
            $InstallRequest.ExpectedStep = 'Attempting'
            Invoke-WorkspaceBridge -PythonPath $PythonPath -Request $InstallRequest -ScratchPath (Join-Path $OperationPath 'scratch')
        }
        Invoke-WorkspaceOrderedApply -Context $Context -Result $Result -State $State -ValidateStep $ValidateStep -InstallStep $InstallStep
        $State.ReceiptHash = Write-WorkspaceOperationReceipt -Context $Context -OperationPath $OperationPath -State Completed -Extensions $Extensions -LastDurableStep Completed -ObservedPaths $Result.ObservedPaths -RecoveryLocations $Result.RecoveryLocations -PreviousSha256 $State.ReceiptHash
        $Result.LastDurableStep = 'Completed'
        Remove-WorkspaceOperationLock $Context
        $Result.State = 'Completed'
    }
    catch {
        if ($Context.PSObject.Properties.Name -contains 'MutationBegan') { $Result.MutationBegan = $Context.MutationBegan }
        if ($Result.MutationBegan) {
            $Result.OperationPath = $OperationPath
            $Result.RecoveryLocations = @($Context.CreatedPaths.ToArray()) + @($OperationPath, (Join-Path $Context.WorkspacePath '.specify/skill-library-install/lock')) + @(
                foreach ($Extension in $Approved.Extensions) {
                    Join-Path $Context.WorkspacePath ".specify/extensions/$($Extension.RootId)"
                }
            )
            try {
                $Observation = Invoke-WorkspaceBridge -PythonPath $PythonPath -Request @{
                    Action = 'observe-failure'; WorkspacePath = $Context.WorkspacePath; ApprovedInputs = $Approved
                }
                if ($Observation.Status -cne 'Inspected') {
                    $Result.Blockers += @($Observation.Blockers)
                    throw 'Failure observations are incomplete.'
                }
                $Result.ObservedPaths = @($Observation.Result.Paths)
            }
            catch {
                $Result.ObservedPaths += [pscustomobject]@{ Path = '.'; Presence = 'unknown'; ObservationError = 'Unavailable' }
                $Result.Blockers += New-WorkspaceConflict OperationState observation 'Some paths could not be inspected; retain previous observations and recovery locations.' -Observed $_.Exception.GetType().Name
            }
        }
        if ($Extensions[0].State -ceq 'Attempting') { $Extensions[0].State = 'Unknown' }
        $Result.State = if ($State.Cancelled) { 'Cancelled' } elseif (@($Extensions | Where-Object State -CEQ 'Unknown').Count) { 'Unknown' } elseif (@($Extensions | Where-Object State -CEQ 'Failed').Count) { 'Failed' } elseif (@($Extensions | Where-Object State -CEQ 'Verified').Count) { 'Unknown' } else { 'Failed' }
        if (-not $Result.Blockers.Count) { $Result.Blockers = @(New-WorkspaceConflict OperationState apply 'Apply stopped; preserve operation and runtime paths and inspect the last durable step.') }
        if ($State.ReceiptHash -and $Result.LastDurableStep -cne 'Completed') {
            try {
                $State.ReceiptHash = Write-WorkspaceOperationReceipt -Context $Context -OperationPath $OperationPath -State $Result.State -Extensions $Extensions -LastDurableStep $Result.State -ObservedPaths $Result.ObservedPaths -RecoveryLocations $Result.RecoveryLocations -PreviousSha256 $State.ReceiptHash
                $Result.LastDurableStep = $Result.State
            }
            catch { $Result.Blockers += New-WorkspaceConflict OperationState receipt 'Outcome evidence could not be flushed; retain all files and the last durable receipt.' }
        }
    }
    $Result.CompletedExtensions = @($Extensions | Where-Object State -CEQ 'Verified')
    $Result.FailedExtensions = @($Extensions | Where-Object State -CEQ 'Failed')
    $Result.UnknownExtensions = @($Extensions | Where-Object State -CEQ 'Unknown')
    $Result.PendingExtensions = @($Extensions | Where-Object State -CEQ 'Pending')
    return $Result
}

function Invoke-SkillWorkspaceInstall {
    [CmdletBinding()]
    param(
        [string]$RepoRoot, [string]$SourceRevision = 'HEAD',
        [string]$SkillName, [string[]]$OptionalSelection = @(),
        [string]$WorkspacePath, [string[]]$CatalogPath = @(),
        [string[]]$ArtifactDirectory = @(), [string]$PythonPath,
        [switch]$Apply, [string]$ReviewedFingerprint, [switch]$Json,
        [string]$PackageIndexPath, [string]$PackageVersion
    )
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version 3.0
    if ($Apply) {
        if ($ReviewedFingerprint -cnotmatch '^[0-9a-f]{64}$') {
            return New-WorkspaceApplyResult -ReviewedFingerprint $ReviewedFingerprint -Blockers @(
                New-WorkspaceConflict ApprovalMismatch approval 'Supply the exact lowercase fingerprint from a ready preview.'
            )
        }
        if ($PackageIndexPath -and $PackageVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
            return New-WorkspaceApplyResult -ReviewedFingerprint $ReviewedFingerprint -Blockers @(
                New-WorkspaceConflict ApprovalMismatch version 'Apply requires the exact packaged root version resolved in the reviewed preview.'
            )
        }
        $PreviewArguments = @{
            RepoRoot = $RepoRoot; SourceRevision = $SourceRevision; SkillName = $SkillName; OptionalSelection = $OptionalSelection
            WorkspacePath = $WorkspacePath; CatalogPath = $CatalogPath
            ArtifactDirectory = $ArtifactDirectory; PythonPath = $PythonPath
            PackageIndexPath = $PackageIndexPath; PackageVersion = $PackageVersion
        }
        $Approved = Invoke-SkillWorkspaceInstall @PreviewArguments
        if (-not $Approved.Ready) {
            return New-WorkspaceApplyResult -ReviewedFingerprint $ReviewedFingerprint -Blockers @($Approved.Blockers)
        }
        if ($Approved.Fingerprint -cne $ReviewedFingerprint) {
            return New-WorkspaceApplyResult -ReviewedFingerprint $ReviewedFingerprint -Blockers @(
                New-WorkspaceConflict ApprovalMismatch approval 'Inputs changed; review a fresh preview before applying.'
            )
        }
        return Invoke-WorkspaceRootApply -Approved $Approved -PythonPath $PythonPath
    }
    $Result = New-WorkspacePreview
    $Blockers = [Collections.Generic.List[object]]::new()
    $Packaged = -not [string]::IsNullOrEmpty($PackageIndexPath)
    if ($Packaged) {
        try {
            Assert-WorkspaceInputPath -Path $PackageIndexPath
            $PackageRoot = [IO.Path]::GetDirectoryName($PackageIndexPath)
            if (($RepoRoot -and $RepoRoot -cne $PackageRoot) -or ($CatalogPath.Count -and ($CatalogPath.Count -ne 1 -or $CatalogPath[0] -cne $PackageIndexPath)) -or $ArtifactDirectory.Count -ne 1) { throw 'Mixed provider inputs.' }
            $RepoRoot = $PackageRoot
            $CatalogPath = @($PackageIndexPath)
        }
        catch { $Blockers.Add((New-WorkspaceConflict Selection source 'Use one explicit packaged index and artifact directory without mixed repository or catalog inputs.')) }
    }
    if ($PSBoundParameters.ContainsKey('ReviewedFingerprint')) { $Blockers.Add((New-WorkspaceConflict ApprovalMismatch preview 'A reviewed fingerprint is accepted only with a supported apply operation.')) }
    if (-not $IsLinux) { $Blockers.Add((New-WorkspaceConflict Prerequisite platform 'Linux is required.')) }
    foreach ($InputPath in @(@{ Path = $RepoRoot; Directory = $true; Code = 'Selection'; Scope = 'source' }, @{ Path = $WorkspacePath; Directory = $true; Code = 'Workspace'; Scope = 'consumer' }, @{ Path = $PythonPath; Directory = $false; Code = 'Prerequisite'; Scope = 'interpreter' })) {
        try { Assert-WorkspaceInputPath -Path $InputPath.Path -Directory:$InputPath.Directory -Executable:($InputPath.Scope -ceq 'interpreter') }
        catch { $Blockers.Add((New-WorkspaceConflict $InputPath.Code $InputPath.Scope 'Supply an existing unambiguous absolute local input without linked ancestors.')) }
    }
    if ($SkillName -cnotmatch '^[a-z0-9][a-z0-9-]*$') { $Blockers.Add((New-WorkspaceConflict Selection root 'Supply exactly one native skill folder selector.')) }
    if ($CatalogPath.Count -eq 0) { $Blockers.Add((New-WorkspaceConflict Catalog inputs 'Supply explicit existing local generated catalogs.')) }
    if ($ArtifactDirectory.Count -eq 0) { $Blockers.Add((New-WorkspaceConflict Artifact inputs 'Supply explicit existing artifact directories.')) }
    foreach ($Group in @(@{ Values = $CatalogPath; Directory = $false; Code = 'Catalog' }, @{ Values = $ArtifactDirectory; Directory = $true; Code = 'Artifact' })) {
        $Seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($Path in $Group.Values) {
            try {
                Assert-WorkspaceInputPath -Path $Path -Directory:$Group.Directory
                if (-not $Seen.Add($Path)) { throw 'Duplicate input.' }
                foreach ($Managed in @('.specify', '.github/skills')) {
                    $Prefix = Join-Path $WorkspacePath $Managed
                    $LibraryRoot = Join-Path $WorkspacePath '.specify/extensions/skill/library'
                    $OwnedPackageInput = $Packaged -and $RepoRoot -ceq $LibraryRoot -and (
                        (-not $Group.Directory -and $Path -ceq (Join-Path $LibraryRoot 'catalog.json')) -or
                        ($Group.Directory -and $Path -ceq (Join-Path $LibraryRoot 'packages'))
                    )
                    if (($Path -ceq $Prefix -or $Path.StartsWith("$Prefix/", [StringComparison]::Ordinal)) -and -not $OwnedPackageInput) { throw 'Managed input.' }
                }
            }
            catch { $Blockers.Add((New-WorkspaceConflict $Group.Code inputs 'Use unique existing absolute unlinked inputs outside managed consumer trees.')) }
        }
    }
    $Selection = $null
    if (@($Blockers | Where-Object { $_.Scope -in @('source', 'root', 'interpreter') }).Count -eq 0) {
        try {
            $Selection = if ($Packaged) {
                Get-WorkspacePackagedSelection -PackageIndexPath $PackageIndexPath -ArtifactDirectory $ArtifactDirectory[0] -SkillName $SkillName -PackageVersion $PackageVersion -OptionalSelection $OptionalSelection -PythonPath $PythonPath
            }
            else { Get-WorkspaceCommittedSelection -Inputs @{ RepoRoot = $RepoRoot; SourceRevision = $SourceRevision; SkillName = $SkillName; OptionalSelection = $OptionalSelection; PythonPath = $PythonPath } }
            $Tools = @($Selection.Tools)
            $WorkspaceTools = @('Invoke-WorkspaceInstall.ps1', 'Invoke-SpecKitInstall.py', 'Invoke-Extension.ps1', 'Git-Process.ps1')
            if (-not $Packaged) { $WorkspaceTools += 'Invoke-InventoryPreview.ps1' }
            foreach ($Relative in $WorkspaceTools) {
                $Path = Join-Path $PSScriptRoot $Relative
                Assert-WorkspaceInputPath $Path
                $Tools += [pscustomobject]@{ Role = 'workspace-tool'; Path = $Path; Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
            }
            $PowerShell = (Get-Process -Id $PID).Path
            $Tools += [pscustomobject]@{ Role = 'powershell'; Path = $PowerShell; Sha256 = (Get-FileHash -LiteralPath $PowerShell -Algorithm SHA256).Hash.ToLowerInvariant(); Version = $PSVersionTable.PSVersion.ToString() }
            $Result.Selection = [pscustomobject]@{
                SourceCommit = $Selection.SourceCommit; SourceRoot = $RepoRoot; Root = $Selection.Root; OptionalSelection = @($Selection.OptionalSelection)
                ActiveComponents = @($Selection.ActiveComponents)
                ExtensionRoots = @(); RequiredInventories = @()
                Tools = $Tools
            }
            if ($Packaged) { $Result.Selection | Add-Member -NotePropertyName SourceKind -NotePropertyValue 'packaged' }
            $Result.OptionalOffers = @($Selection.OptionalOffers)
            for ($Position = 0; $Position -lt $Selection.ExtensionRoots.Count; $Position++) {
                $Root = $Selection.ExtensionRoots[$Position]
                $Required = if ($Packaged) {
                    [pscustomobject]@{ Root = $Root; SourceCommit = $Selection.RequiredInventories[$Position].SourceCommit; Inventory = $Selection.RequiredInventories[$Position].Inventory; Payload = @($Selection.RequiredInventories[$Position].Payload) }
                }
                elseif ($Selection.OptionalSelection.Count -eq 0) { $Selection } else {
                    Get-WorkspaceCommittedSelection -Inputs @{ RepoRoot = $RepoRoot; SourceRevision = $Selection.SourceCommit; SkillName = [IO.Path]::GetFileName($Root.Folder); PythonPath = $PythonPath }
                }
                $ExpectedCommit = if ($Packaged) { $Root.SourceCommit } else { $Selection.SourceCommit }
                if ($Required.SourceCommit -cne $ExpectedCommit -or $Required.Root.Id -cne $Root.Id -or $Required.Root.Version -cne $Root.Version) { throw 'Required inventory identity changed.' }
                $Result.Selection.ExtensionRoots += [pscustomobject]@{ Position = $Position; Id = $Root.Id; Version = $Root.Version; Folder = $Root.Folder; SourceCommit = $Required.SourceCommit }
                $Result.Selection.RequiredInventories += [pscustomobject]@{ Position = $Position; SourceCommit = $Required.SourceCommit; Inventory = $Required.Inventory; Payload = @($Required.Payload) }
            }
            $Resources = @(
                for ($Position = 0; $Position -lt $Result.Selection.RequiredInventories.Count; $Position++) {
                    foreach ($File in $Result.Selection.RequiredInventories[$Position].Payload) {
                        [pscustomobject]@{ SourcePath = $File.SourcePath; Sha256 = $File.Sha256; ExtensionId = $Result.Selection.ExtensionRoots[$Position].Id }
                    }
                }
            )
            $Result.Overlaps = @(
                foreach ($Group in ($Resources | Group-Object SourcePath)) {
                    if ($Group.Count -gt 1) {
                        if (@($Group.Group.Sha256 | Select-Object -Unique).Count -ne 1) { throw 'Overlapping committed bytes disagree.' }
                        [pscustomobject]@{ SourcePath = $Group.Name; Sha256 = $Group.Group[0].Sha256; ExtensionIds = @($Group.Group.ExtensionId | Sort-Object -CaseSensitive) }
                    }
                }
            )
        }
        catch { $Blockers.Add((New-WorkspaceConflict Selection committed 'Restore valid committed metadata, exact pins, source paths and trusted inventory tools; no working-file fallback is used.')) }
    }
        if ($Result.Selection -and @($Blockers | Where-Object Code -CEQ 'Selection').Count -eq 0) {
            for ($Position = 0; $Position -lt $Result.Selection.ExtensionRoots.Count; $Position++) {
                $Root = $Result.Selection.ExtensionRoots[$Position]
                $Required = $Result.Selection.RequiredInventories[$Position]
                $ArtifactSelection = [pscustomobject]@{ Root = [pscustomobject]@{ Id = $Root.Id; Version = $Root.Version; Folder = $Root.Folder }; SourceCommit = $Required.SourceCommit; Inventory = $Required.Inventory; Payload = @($Required.Payload) }
        $Catalog = $null
        if (@($Blockers | Where-Object Code -CEQ 'Catalog').Count -eq 0) {
            try {
                $Response = Invoke-WorkspaceBridge -PythonPath $PythonPath -Request @{ Action = 'catalog'; Root = $ArtifactSelection.Root; CatalogPath = @($CatalogPath); SourceKind = $(if ($Packaged) { 'packaged' } else { 'committed' }) }
                if ($Response.Status -ceq 'Inspected') { $Catalog = $Response.Result } else { foreach ($Conflict in $Response.Blockers) { $Blockers.Add($Conflict) } }
            }
            catch { $Blockers.Add((New-WorkspaceConflict Catalog local 'Restore a unique strictly parsed generated local catalog.')) }
        }
        if ($Catalog -and @($Blockers | Where-Object Code -CEQ 'Artifact').Count -eq 0) {
            try {
                $Candidates = @(
                    foreach ($Directory in $ArtifactDirectory) {
                        $Path = Join-Path $Directory "$($Root.Id)-$($Root.Version).zip"
                        if (Test-Path -LiteralPath $Path) { Assert-WorkspaceInputPath $Path; $Path }
                    }
                )
                if ($Candidates.Count -ne 1) { throw 'Missing or duplicate selected candidate.' }
                $Response = Invoke-WorkspaceBridge -PythonPath $PythonPath -Request @{
                    Action = 'verify'; Selection = $ArtifactSelection; Catalog = $Catalog.Record; ArchivePath = $Candidates[0]
                }
                if ($Response.Status -ceq 'Inspected') {
                    $Extension = $Response.Result
                    $Extension | Add-Member -NotePropertyName CatalogOrigins -NotePropertyValue @($Catalog.CatalogOrigins)
                    $Extension | Add-Member -NotePropertyName ArtifactOrigins -NotePropertyValue @($ArtifactDirectory | ForEach-Object { [pscustomobject]@{ Path = $_ } })
                    $Extension.Position = $Position
                    $Result.Extensions += $Extension
                    $Result.IntendedWrites += Get-WorkspaceIntendedWrites -Extension $Extension -Position $Position
                }
                else { foreach ($Conflict in $Response.Blockers) { $Blockers.Add($Conflict) } }
            }
            catch { $Blockers.Add((New-WorkspaceConflict Artifact local 'Supply one verified selected prebuilt extension with exact committed evidence; no fallback or rebuild occurs.')) }
        }
            }
    }
    if (@($Blockers | Where-Object { $_.Scope -in @('consumer', 'interpreter', 'source') }).Count -eq 0) {
        try {
            $SnapshotArguments = @{ RepoRoot = $RepoRoot; WorkspacePath = $WorkspacePath; PythonPath = $PythonPath; IntendedWrites = @($Result.IntendedWrites); SourceKind = $(if ($Packaged) { 'packaged' } else { 'committed' }) }
            if ($Result.Selection) { $SnapshotArguments.RootIds = @($Result.Selection.ExtensionRoots.Id) }
            $Response = Get-WorkspaceConsumerSnapshot @SnapshotArguments
            if ($Response.Status -ceq 'Inspected') {
                $Result.ConsumerSnapshot = $Response.Result.ConsumerSnapshot
                if ($Result.ConsumerSnapshot.ConfigurationPrediction) {
                    foreach ($Write in $Result.IntendedWrites) {
                        if ($Write.Path -ceq '.specify/extensions.yml') { $Write.Sha256 = $Result.ConsumerSnapshot.ConfigurationPredictions[$Write.Position].Sha256 }
                    }
                }
            }
            else { foreach ($Conflict in $Response.Blockers) { $Blockers.Add($Conflict) } }
        }
        catch { $Blockers.Add((New-WorkspaceConflict Prerequisite inspection 'Restore supported readable runtime and consumer state.')) }
    }
    $Result.Blockers = @($Blockers.ToArray())
    if ($Blockers.Count -eq 0 -and $Result.Selection -and $Result.Extensions.Count -eq $Result.Selection.ExtensionRoots.Count -and $Result.Extensions.Count -gt 0 -and $Result.ConsumerSnapshot) {
        try {
            $Result.Fingerprint = Get-WorkspaceFingerprint -PythonPath $PythonPath -Projection $Result
            foreach ($Write in $Result.IntendedWrites) { $Write.Path = $Write.Path.Replace('{operation}', $Result.Fingerprint) }
            $Result.Ready = $true
        }
        catch {
            $Result.Fingerprint = $null
            $Result.Blockers = @(New-WorkspaceConflict VerificationFailure fingerprint 'Restore supported canonical approval evidence; no ready preview was produced.')
        }
    }
    return $Result
}
#endregion

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version 3.0
    try {
        if ($LibraryRequest) {
            if (-not $Json -or @($PSBoundParameters.Keys | Where-Object { $_ -cnotin @('LibraryRequest', 'Json') }).Count) { throw 'Structured request cannot be mixed with other inputs.' }
            $Buffer = [char[]]::new(1MB + 1)
            $Length = [Console]::In.ReadBlock($Buffer, 0, $Buffer.Length)
            if ($Length -gt 1MB) { throw 'Structured request exceeds its bound.' }
            $Request = [string]::new($Buffer, 0, $Length) | ConvertFrom-Json -AsHashtable -Depth 40
            $Required = @('PackageIndexPath', 'SkillName', 'WorkspacePath', 'ArtifactDirectory', 'PythonPath')
            $Allowed = $Required + @('PackageVersion', 'OptionalSelection', 'Apply', 'ReviewedFingerprint')
            if ($Request -isnot [Collections.IDictionary] -or @($Request.Keys | Where-Object { $_ -cnotin $Allowed }).Count -or @($Required | Where-Object { -not $Request.ContainsKey($_) }).Count) { throw 'Invalid structured request fields.' }
            foreach ($Key in @('PackageIndexPath', 'SkillName', 'WorkspacePath', 'PythonPath', 'PackageVersion', 'ReviewedFingerprint')) {
                if ($Request.ContainsKey($Key) -and $Request[$Key] -isnot [string]) { throw 'Invalid structured scalar.' }
            }
            foreach ($Key in @('ArtifactDirectory', 'OptionalSelection')) {
                if ($Request.ContainsKey($Key) -and ($Request[$Key] -isnot [array] -or @($Request[$Key] | Where-Object { $_ -isnot [string] }).Count)) { throw 'Invalid structured array.' }
            }
            if ($Request.ContainsKey('Apply') -and $Request.Apply -isnot [bool]) { throw 'Invalid structured apply flag.' }
            $Result = Invoke-SkillWorkspaceInstall @Request
        }
        else { $Result = Invoke-SkillWorkspaceInstall @PSBoundParameters }
        if ($Json) { ConvertTo-Json -InputObject $Result -Depth 100 } else { $Result }
        exit (Get-WorkspaceExitCode $Result)
    }
    catch {
        [Console]::Error.WriteLine('Workspace operation failed unexpectedly; inspect retained operation evidence before retrying.')
        exit 4
    }
}
#endregion
