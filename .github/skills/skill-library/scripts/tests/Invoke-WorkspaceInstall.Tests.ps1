#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Invoke-VersionPreparation.ps1')
    $script:Python = if ($env:SKILL_LIBRARY_TEST_PYTHON) { $env:SKILL_LIBRARY_TEST_PYTHON } else { 'python3' }
    $script:WorkspaceScript = Join-Path $PSScriptRoot '../Invoke-WorkspaceInstall.ps1'
    $script:Bridge = Join-Path $PSScriptRoot '../Invoke-SpecKitInstall.py'
    $FixtureSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-InventoryPreview.Tests.ps1'))
    $FixtureAst = [Management.Automation.Language.Parser]::ParseInput($FixtureSource, [ref]$null, [ref]$null)
    foreach ($Definition in $FixtureAst.FindAll({ param($Node) $Node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($Definition.Name -in @('Assert-InventoryFixtureRoot', 'Invoke-InventoryGit', 'Set-InventoryFile', 'Set-InventorySkill', 'Save-InventoryFixture', 'New-InventoryFixture', 'Get-InventoryState')) {
            . ([scriptblock]::Create($Definition.Extent.Text))
        }
    }
    if (Test-Path -LiteralPath $script:WorkspaceScript) { . $script:WorkspaceScript }
    $script:ReserveEvidence = (Get-Command New-WorkspaceOperationEvidence).ScriptBlock
    $script:ReleaseLock = (Get-Command Remove-WorkspaceOperationLock).ScriptBlock
    $script:RealBridge = (Get-Command Invoke-WorkspaceBridge).ScriptBlock

    function New-WorkspaceFixture {
        $Root = New-InventoryFixture
        Set-InventorySkill $Root 'shared'
        Set-InventoryFile $Root '.github/skills/shared/references/detail.md' "# Shared resource`n"
        Set-InventoryFile $Root '.github/skills/shared/references/data.bin' -Bytes ([byte[]]@(0, 255, 13, 10, 128))
        Set-InventorySkill $Root 'nested'
        Set-InventorySkill $Root 'declined'
        Set-InventorySkill $Root 'peer' @{
            required = @(@{ id = 'shared'; version = '1.0.0' })
            optional = @(@{ id = 'nested'; version = '1.0.0'; selectionKey = 'nested'; reason = 'Nested synthetic offer.' })
        }
        Set-InventorySkill $Root 'example' @{
            required = @(@{ id = 'shared'; version = '1.0.0' })
            optional = @(
                @{ id = 'peer'; version = '1.0.0'; selectionKey = 'peer'; reason = 'Related synthetic guidance.' },
                @{ id = 'declined'; version = '1.0.0'; selectionKey = 'declined'; reason = 'Separate synthetic choice.' }
            )
        }
        Set-InventoryFile $Root '.github/skills/example/SKILL.md' "---`nname: example`ndescription: Synthetic fixture.`n---`n# Example`n[Unselected link](../declined/SKILL.md)`n"
        [void](Save-InventoryFixture $Root)
        return $Root
    }

    function Set-WorkspaceArtifact {
        param([string]$SourceRoot, [string]$Destination, [string]$SkillName = 'example')
        [void][IO.Directory]::CreateDirectory($Destination)
        $Selection = Get-SkillCommittedSelection -RepoRoot $SourceRoot -SkillName $SkillName -PythonPath $script:Python
        $Identity = $Selection.Root.Id
        $Description = "Packaged $Identity skill and its required resources."
        $Manifest = [ordered]@{
            SchemaVersion = 1; SourceCommit = $Selection.SourceCommit; Root = $Selection.Root
            OptionalSelections = @(); Builder = @{ Contract = 'skill-archive/1' }
            Components = @($Selection.Inventory.Components); Payload = @($Selection.Payload)
            GeneratedMembers = @(@{ Path = 'manifest.json'; Role = 'build-evidence'; Mode = '100644' })
            Limitations = @('Synthetic fixture; no rights clearance.')
        }
        $RuntimeManifest = @{
            schema_version = '1.0'
            extension = @{ id = $Identity; name = $Identity; version = '1.0.0'; description = $Description; effect = 'read-only' }
            requires = @{ speckit_version = '==1.2.3' }
            provides = @{ templates = @(@{ name = $Identity; file = "resources/library/$($Selection.Root.Folder)/SKILL.md"; description = $Description }) }
        }
        $Members = [ordered]@{
            'extension.yml' = [Text.Encoding]::UTF8.GetBytes(($RuntimeManifest | ConvertTo-Json -Depth 40))
            'source-manifest.json' = [Text.Encoding]::UTF8.GetBytes(($Manifest | ConvertTo-Json -Depth 40))
            'extension-build.json' = [Text.Encoding]::UTF8.GetBytes((@{ Contract = 'skill-extension/1'; SourceArchiveSha256 = 'a' * 64; SourceCommit = $Selection.SourceCommit; Root = $Selection.Root; SpecKitVersion = '1.2.3' } | ConvertTo-Json -Depth 10))
        }
        foreach ($File in $Selection.Payload) {
            $Read = Invoke-LibraryGit -Root $SourceRoot -Arguments @('show', "$($Selection.SourceCommit):$($File.SourcePath)")
            if ($Read.ExitCode) { throw 'Synthetic committed payload unavailable.' }
            $Members["resources/library/$($File.SourcePath)"] = $Read.Bytes
        }
        $Path = Join-Path $Destination "$Identity-1.0.0.zip"
        $Zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($Name in $Members.Keys) {
                $Entry = $Zip.CreateEntry($Name, [IO.Compression.CompressionLevel]::NoCompression)
                $Entry.ExternalAttributes = [Convert]::ToInt32('100644', 8) -shl 16
                $Stream = $Entry.Open()
                try { $Stream.Write([byte[]]$Members[$Name]) } finally { $Stream.Dispose() }
            }
        }
        finally { $Zip.Dispose() }
        $Catalog = @{ schema_version = '1.0'; extensions = @{ $Identity = @{
            name = $Identity; description = $Description; version = '1.0.0'; download_url = "https://example.com/$Identity-1.0.0.zip"
            sha256 = (Get-FileHash $Path).Hash.ToLowerInvariant(); requires = $RuntimeManifest.requires; provides = $RuntimeManifest.provides
        } } }
        [IO.File]::WriteAllText((Join-Path $Destination 'catalog.json'), ($Catalog | ConvertTo-Json -Depth 40))
        [IO.File]::WriteAllText((Join-Path $Destination 'declined-1.0.0.zip'), 'Armed declined artifact: not a ZIP.')
    }

    function Invoke-WorkspaceFixture {
        param([hashtable]$Extra = @{})
        $Inputs = @{} + $script:Inputs
        foreach ($Key in $Extra.Keys) { $Inputs[$Key] = $Extra[$Key] }
        Invoke-SkillWorkspaceInstall @Inputs
    }

    function Invoke-SyntheticWorkspaceApply {
        param([hashtable]$Request, [string]$PythonPath, [string]$ScratchPath)
        $Program = @'
import io, json, os, runpy, signal, sys, tempfile, types, warnings, zipfile
from datetime import datetime, timezone
from pathlib import Path
request = json.loads(sys.stdin.read())
namespace = runpy.run_path(sys.argv[1])
helpers = namespace["_dispatch"].__globals__
import specify_cli.extensions, yaml
index = request.get("StepIndex", 0)
extension = request["ApprovedInputs"]["Extensions"][index]
identity = extension["RootId"]
if request.get("SyntheticPeerFault") and identity != "peer":
    request["SyntheticFault"] = ""
verified_stream = None
original_verify = helpers["_verify_artifact"]
def verify(arguments, stream=None):
    global verified_stream
    result = original_verify(arguments, stream)
    if stream is not None:
        verified_stream = stream
    return result
helpers["_verify_artifact"] = verify
archive_opens = 0
def audit(event, arguments):
    global archive_opens
    if event.startswith("socket."):
        raise RuntimeError("Synthetic network tripwire")
    if event == "open" and str(arguments[0]).endswith(("declined-1.0.0.zip", "nested-1.0.0.zip")):
        raise RuntimeError("Synthetic declined archive tripwire")
    if event == "open" and str(arguments[0]) == extension["Archive"]["Path"]:
        archive_opens += 1
sys.addaudithook(audit)
class SyntheticManager:
    def __init__(self, workspace):
        self.root = Path(workspace)
        receipt = json.loads((Path(request["OperationPath"]) / "operation.json").read_text())
        assert receipt["LastDurableStep"] == "Attempting"
        assert receipt["State"] == "Running" and receipt["Extensions"][index]["State"] == "Attempting"
        assert all(item["State"] == "Verified" for item in receipt["Extensions"][:index])
        if request.get("SyntheticFault") == "constructor":
            raise RuntimeError("SYNTHETIC_UNSAFE_DETAIL")
    def install_from_archive(self, archive_path, speckit_version, priority=10, force=False, *, archive_file=None, expected_id=None, expected_version=None):
        assert speckit_version == "1.2.3" and priority == 10 and force is False
        assert expected_id == identity and expected_version == "1.0.0"
        assert archive_file is verified_stream and archive_file.tell() == 0 and archive_opens == 1
        scratch = Path(request["OperationPath"]) / "scratch"
        assert Path(tempfile.gettempdir()) == scratch and os.environ["TMPDIR"] == str(scratch)
        with tempfile.TemporaryDirectory() as temporary:
            assert Path(temporary).parent == scratch
        target = self.root / f".specify/extensions/{identity}"
        fault = request.get("SyntheticFault", "")
        if fault in ("before-copy", "kill-before-copy"):
            if fault.startswith("kill-"):
                os.kill(os.getpid(), signal.SIGKILL)
            raise KeyboardInterrupt("SYNTHETIC_UNSAFE_DETAIL")
        target.mkdir(mode=0o700, parents=True)
        with zipfile.ZipFile(archive_file) as archive:
            for entry in archive.infolist():
                path = target / entry.filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(archive.read(entry))
                path.chmod((entry.external_attr >> 16) & 0o777)
        if fault in ("copy", "kill-copy"):
            if fault.startswith("kill-"):
                os.kill(os.getpid(), signal.SIGKILL)
            raise KeyboardInterrupt("SYNTHETIC_UNSAFE_DETAIL")
        registry_path = self.root / ".specify/extensions/.registry"
        registry = json.loads(registry_path.read_text()) if registry_path.exists() else {"schema_version": "1.0", "extensions": {}}
        addition = dict(extension["RegistryAddition"])
        assert addition["registered_commands"] == {}
        addition["installed_at"] = datetime.now(timezone.utc).isoformat()
        registry["extensions"][identity] = addition
        registry_path.write_text(json.dumps(registry, indent=2))
        if fault in ("registration", "kill-registration"):
            if fault.startswith("kill-"):
                os.kill(os.getpid(), signal.SIGKILL)
            raise KeyboardInterrupt("SYNTHETIC_UNSAFE_DETAIL")
        config_path = self.root / ".specify/extensions.yml"
        config = yaml.safe_load(config_path.read_text()) if config_path.exists() else {"installed": [], "settings": {"auto_execute_hooks": True}, "hooks": {}}
        config["installed"] = sorted([*config["installed"], identity])
        config_path.write_text(yaml.dump(config, default_flow_style=False, sort_keys=False, allow_unicode=True))
        fault = request.get("SyntheticFault", "")
        if fault == "notice":
            (target / "resources/library/LICENSE").write_text("Synthetic corruption")
        elif fault == "command":
            command = self.root / f".github/skills/speckit-{identity}-load/SKILL.md"
            command.parent.mkdir(parents=True, exist_ok=True)
            command.write_text("Unapproved synthetic command")
        elif fault == "registry":
            registry["extensions"][identity]["registered_skills"] = ["unexpected-synthetic-command"]
            registry_path.write_text(json.dumps(registry, indent=2))
        elif fault == "extra":
            (target / "unapproved.txt").write_text("Synthetic addition")
        elif fault == "mode":
            (target / "resources/library/LICENSE").chmod(0o755)
        elif fault == "unrelated":
            (self.root / ".specify/scripts/preserve.txt").write_text("Synthetic corruption")
        elif fault == "warning":
            print("SYNTHETIC_UNSAFE_DETAIL")
            print("SYNTHETIC_UNSAFE_DETAIL", file=sys.stderr)
            warnings.warn("SYNTHETIC_UNSAFE_DETAIL", RuntimeWarning)
        elif fault == "raise":
            raise RuntimeError("SYNTHETIC_UNSAFE_DETAIL")
        elif fault == "cancel":
            raise KeyboardInterrupt("SYNTHETIC_UNSAFE_DETAIL")
        elif fault == "observe":
            (target / "unreadable-link").symlink_to(target / "resources/library/LICENSE")
            raise RuntimeError("SYNTHETIC_UNSAFE_DETAIL")
        elif fault == "malformed":
            os.write(1, b'{"Status":')
            os._exit(3)
        elif fault == "kill-verified":
            os.kill(os.getpid(), signal.SIGKILL)
        return types.SimpleNamespace(id=identity, version="1.0.0+drift" if fault == "version" else "1.0.0", warnings=[])
specify_cli.extensions.ExtensionManager = SyntheticManager
sys.stdin = io.StringIO(json.dumps(request))
raise SystemExit(namespace["main"]())
'@
        $Request.SyntheticFault = $script:ApplyFault
        $ActiveFault = $script:ApplyFault
        if ($Request.ContainsKey('SyntheticPeerFault') -and $Request.SyntheticPeerFault -and $Request.ApprovedInputs.Extensions[$Request.StepIndex].RootId -cne 'peer') { $ActiveFault = '' }
        $SyntheticProfile = New-InventoryFixture
        Set-InventoryFile $SyntheticProfile '.copilot/instructions/preserve.instructions.md' 'Preserve synthetic profile guidance.'
        $ProfileBefore = Get-InventoryState $SyntheticProfile
        $Process = Invoke-LibraryProcess -Executable $PythonPath -Arguments @('-I', '-B', '-c', $Program, $script:Bridge) -Environment @{ TMPDIR = $ScratchPath; HOME = $SyntheticProfile; XDG_CONFIG_HOME = (Join-Path $SyntheticProfile '.config') } -InputBytes ([Text.Encoding]::UTF8.GetBytes(($Request | ConvertTo-Json -Depth 100)))
        Get-InventoryState $SyntheticProfile | Should -BeExactly $ProfileBefore
        $Process.Error | Should -BeNullOrEmpty
        $Text = [Text.Encoding]::UTF8.GetString($Process.Bytes)
        $Text | Should -Not -Match 'SYNTHETIC_UNSAFE_DETAIL|Traceback'
        if ($ActiveFault -like 'kill-*' -or $ActiveFault -ceq 'malformed') {
            $Process.ExitCode | Should -Not -Be 0
            throw 'Synthetic child returned no trustworthy outcome.'
        }
        $Response = $Text | ConvertFrom-Json -Depth 100
        $Process.ExitCode | Should -BeIn @(0, 3)
        return $Response
    }

    function Set-WorkspaceZipFault {
        param([string]$Fault)
        $Path = Join-Path $script:Inputs.ArtifactDirectory[0] 'example-1.0.0.zip'
        $Zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Update)
        try {
            switch ($Fault) {
                'notice' { $Zip.GetEntry('resources/library/LICENSE').Delete() }
                'mode' { $Zip.GetEntry('resources/library/LICENSE').ExternalAttributes = [Convert]::ToInt32('100755', 8) -shl 16 }
                'link' { $Zip.GetEntry('resources/library/LICENSE').ExternalAttributes = [Convert]::ToInt32('120777', 8) -shl 16 }
                'raw-bytes' { $Zip.Comment = 'Synthetic bound header change.' }
                default {
                    $Name = if ($Fault -eq 'duplicate-json') { 'source-manifest.json' } elseif ($Fault -eq 'duplicate-yaml') { 'extension.yml' } elseif ($Fault -eq 'traversal') { '../escape' } elseif ($Fault -eq 'extra') { 'extra.txt' } elseif ($Fault -eq 'oversize-member') { 'large.bin' } else { 'extension.yml' }
                    $Original = $Zip.GetEntry($Name)
                    $Text = 'Synthetic changed content.'
                    if ($Original -and $Fault -ne 'duplicate-member') {
                        $Reader = [IO.StreamReader]::new($Original.Open())
                        try { $Text = $Reader.ReadToEnd() } finally { $Reader.Dispose() }
                        $Original.Delete()
                    }
                    if ($Fault -eq 'duplicate-json') { $Text = '{"SchemaVersion":1,' + $Text.TrimStart().Substring(1) }
                    elseif ($Fault -eq 'duplicate-yaml') { $Text = '{"schema_version":"1.0",' + $Text.TrimStart().Substring(1) }
                    $Entry = $Zip.CreateEntry($Name, [IO.Compression.CompressionLevel]::NoCompression)
                    $Entry.ExternalAttributes = [Convert]::ToInt32('100644', 8) -shl 16
                    $Stream = $Entry.Open()
                    try {
                        if ($Fault -eq 'oversize-member') { $Stream.Write([byte[]]::new(16MB + 1)) }
                        else { $Stream.Write([Text.Encoding]::UTF8.GetBytes($Text)) }
                    }
                    finally { $Stream.Dispose() }
                }
            }
        }
        finally { $Zip.Dispose() }
        $CatalogPath = $script:Inputs.CatalogPath[0]
        $Catalog = [IO.File]::ReadAllText($CatalogPath) | ConvertFrom-Json -AsHashtable
        $Catalog.extensions.example.sha256 = (Get-FileHash $Path).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($CatalogPath, ($Catalog | ConvertTo-Json -Depth 40))
    }

    function Invoke-ArmedWorkspaceProbe {
        param([string[]]$OptionalSelection = @())
        $Probe = @'
import json, os, runpy, sys
namespace = runpy.run_path(sys.argv[1])
import specify_cli.extensions, zipfile
counts = {"Install": 0, "Network": 0, "Extract": 0, "Write": 0, "Declined": 0}
def install(*args, **kwargs):
    counts["Install"] += 1
    raise RuntimeError("Armed install spy")
def extract(*args, **kwargs):
    counts["Extract"] += 1
    raise RuntimeError("Armed extraction spy")
specify_cli.extensions.ExtensionManager.__init__ = install
zipfile.ZipFile.extractall = extract
zipfile.ZipFile.extract = extract
def audit(event, arguments):
    if event.startswith("socket."):
        counts["Network"] += 1
        raise RuntimeError("Armed network spy")
    if event in {"os.mkdir", "os.remove", "os.rename", "os.rmdir", "os.chmod", "os.symlink", "os.link", "tempfile.mkdtemp"}:
        counts["Write"] += 1
        raise RuntimeError("Armed filesystem spy")
    if event == "open":
        path, mode, flags = arguments
        if str(path).endswith(("declined-1.0.0.zip", "nested-1.0.0.zip")):
            counts["Declined"] += 1
            raise RuntimeError("Armed declined-artifact spy")
        if (isinstance(mode, str) and any(char in mode for char in "wxa+")) or (isinstance(flags, int) and flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC)):
            counts["Write"] += 1
            raise RuntimeError("Armed filesystem spy")
sys.addaudithook(audit)
for tripwire in (lambda: install(None), lambda: extract(None), lambda: sys.audit("socket.connect", None), lambda: sys.audit("os.mkdir", "tripwire", 0o700, -1), lambda: sys.audit("open", "declined-1.0.0.zip", "r", 0)):
    try:
        tripwire()
    except RuntimeError:
        pass
armed = dict(counts)
for key in counts:
    counts[key] = 0
request = json.load(sys.stdin)
try:
    for step in request["Steps"]:
        catalog = namespace["_dispatch"](step["Catalog"])
        step["Verify"]["Catalog"] = catalog["Record"]
        extension = namespace["_dispatch"](step["Verify"])
    result = namespace["_dispatch"](request["Probe"])
    response = {"Status": "Inspected", "Result": result}
except namespace["_InspectionError"]:
    response = {"Status": "Blocked"}
response["Spies"] = counts
response["Armed"] = armed
sys.stdout.write(json.dumps(response))
'@
        $Selection = Get-SkillCommittedSelection -RepoRoot $script:Inputs.RepoRoot -SkillName example -OptionalSelection $OptionalSelection -PythonPath $script:Python
        $Request = @{
            Probe = @{ Contract = 'skill-workspace-install/1'; Mode = 'inspect'; Action = 'probe'; RepoRoot = $script:Inputs.RepoRoot; WorkspacePath = $script:Inputs.WorkspacePath; RootIds = @($Selection.ExtensionRoots.Id) }
            Steps = @(
                foreach ($Root in $Selection.ExtensionRoots) {
                    $Required = Get-SkillCommittedSelection -RepoRoot $script:Inputs.RepoRoot -SourceRevision $Selection.SourceCommit -SkillName ([IO.Path]::GetFileName($Root.Folder)) -PythonPath $script:Python
                    $Archive = @($script:Inputs.ArtifactDirectory | ForEach-Object { Join-Path $_ "$($Root.Id)-$($Root.Version).zip" } | Where-Object { Test-Path -LiteralPath $_ })
                    @{
                        Catalog = @{ Contract = 'skill-workspace-install/1'; Mode = 'inspect'; Action = 'catalog'; Root = $Required.Root; CatalogPath = $script:Inputs.CatalogPath }
                        Verify = @{ Contract = 'skill-workspace-install/1'; Mode = 'inspect'; Action = 'verify'; Selection = $Required; ArchivePath = $Archive[0] }
                    }
                }
            )
        }
        $Process = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $Probe, $script:Bridge) -InputBytes ([Text.Encoding]::UTF8.GetBytes(($Request | ConvertTo-Json -Depth 100)))
        $Process.ExitCode | Should -Be 0 -Because $Process.Error
        return [Text.Encoding]::UTF8.GetString($Process.Bytes) | ConvertFrom-Json
    }
}

Describe 'Workspace preview contract' -Tag 'Unit' {
    It 'exposes an inert dot-sourceable workspace entry point' {
        Test-Path -LiteralPath $script:WorkspaceScript -PathType Leaf | Should -BeTrue
        $Result = . $script:WorkspaceScript
        $Result | Should -BeNullOrEmpty
        Get-Command Invoke-SkillWorkspaceInstall -CommandType Function | Should -Not -BeNullOrEmpty
    }

    It 'reuses the authoritative graph and offers only active optional edges' {
        $Root = New-WorkspaceFixture
        . (Join-Path $PSScriptRoot '../Invoke-InventoryPreview.ps1')
        $Selection = Get-SkillCommittedSelection -RepoRoot $Root -SkillName example -PythonPath $script:Python
        $Selection.Root.Id | Should -BeExactly 'example'
        $Selection.Inventory.Components.Id | Should -Contain 'shared'
        $Selection.OptionalOffers.Count | Should -Be 2
        @($Selection.OptionalOffers | Where-Object Selected).Count | Should -Be 0
        @($Selection.OptionalOffers | Where-Object TargetId -EQ 'nested').Count | Should -Be 0
    }
}

Describe 'Bounded workspace root installation' -Tag 'Unit' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../Invoke-InventoryPreview.ps1')
        $script:SourceRoot = New-WorkspaceFixture
        $script:FixtureArtifacts = Join-Path $TestDrive 'prepared'
        Set-WorkspaceArtifact $script:SourceRoot $script:FixtureArtifacts
        function Set-WorkspaceLibraryFixture {
            param([string]$Directory)
            $Catalog = Get-Content -LiteralPath $script:Inputs.CatalogPath[0] -Raw | ConvertFrom-Json -AsHashtable
            $Packages = Join-Path $Directory 'packages'
            [void][IO.Directory]::CreateDirectory($Packages)
            [IO.File]::Copy((Join-Path $script:Inputs.ArtifactDirectory[0] 'example-1.0.0.zip'), (Join-Path $Packages 'example-1.0.0.zip'))
            $IndexPath = Join-Path $Directory 'catalog.json'
            $Index = @{ schema_version = 'skill-library/1'; skills = @{ example = @{
                        current = '1.0.0'; releases = @{ '1.0.0' = @{ archive = 'example-1.0.0.zip'; catalog = $Catalog.extensions.example } }
                    } } }
            foreach ($Identity in @('peer', 'declined', 'nested')) {
                $Record = @{
                    name = $Identity; description = "Packaged $Identity skill and its required resources."
                    version = '1.0.0'; download_url = "https://example.com/$Identity-1.0.0.zip"; sha256 = '0' * 64
                    requires = @{ speckit_version = '==1.2.3' }
                    provides = @{ templates = @(@{ name = $Identity; file = "resources/library/.github/skills/$Identity/SKILL.md"; description = "Packaged $Identity skill and its required resources." }) }
                }
                $Index.skills[$Identity] = @{ current = '1.0.0'; releases = @{ '1.0.0' = @{ archive = "$Identity-1.0.0.zip"; catalog = $Record } } }
            }
            [IO.File]::WriteAllText($IndexPath, ($Index | ConvertTo-Json -Depth 40))
            return @{ PackageIndexPath = $IndexPath; SkillName = 'example'; WorkspacePath = $script:Inputs.WorkspacePath; ArtifactDirectory = @($Packages); PythonPath = $script:Inputs.PythonPath }
        }
    }

    BeforeEach {
        $Consumer = New-InventoryFixture
        Set-InventoryFile $Consumer '.specify/init-options.json' '{"ai":"copilot","ai_skills":true}'
        $Artifacts = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($Artifacts)
        foreach ($Item in Get-ChildItem -LiteralPath $script:FixtureArtifacts) { [IO.File]::Copy($Item.FullName, (Join-Path $Artifacts $Item.Name)) }
        $script:Inputs = @{
            RepoRoot = $script:SourceRoot; SkillName = 'example'; WorkspacePath = $Consumer
            CatalogPath = @((Join-Path $Artifacts 'catalog.json')); ArtifactDirectory = @($Artifacts)
            PythonPath = (Get-Command $script:Python -CommandType Application -TotalCount 1).Source
        }
    }

    It 'accepts stock pinned Copilot initialization and verifies its recorded integration files' {
        $Root = $script:Inputs.WorkspacePath
        Set-InventoryFile $Root '.specify/init-options.json' '{"ai":"copilot","ai_skills":true,"allow_symlinks":false,"feature_numbering":"sequential","here":true,"integration":"copilot","script":"ps","speckit_version":"1.2.3"}'
        Set-InventoryFile $Root '.specify/integration.json' '{"version":"1.2.3","integration_state_schema":1,"installed_integrations":["copilot"],"integration_settings":{"copilot":{"script":"ps","raw_options":"--skills","parsed_options":{"skills":true},"invoke_separator":"-"}},"integration":"copilot","default_integration":"copilot"}'
        Set-InventoryFile $Root '.github/skills/speckit-plan/SKILL.md' 'Synthetic pinned core command.'
        $Digest = (Get-FileHash (Join-Path $Root '.github/skills/speckit-plan/SKILL.md')).Hash.ToLowerInvariant()
        $Manifest = @{ integration = 'copilot'; version = '1.2.3'; installed_at = '2026-01-01T00:00:00+00:00'; files = @{ '.github/skills/speckit-plan/SKILL.md' = $Digest } }
        Set-InventoryFile $Root '.specify/integrations/copilot.manifest.json' ($Manifest | ConvertTo-Json -Depth 10)
        $CoreManifest = @{ integration = 'speckit'; version = '1.2.3'; installed_at = '2026-01-01T00:00:00+00:00'; files = @{} }
        foreach ($Path in @('.specify/scripts/powershell/setup-plan.ps1', '.specify/templates/plan-template.md', '.specify/.gitignore')) {
            Set-InventoryFile $Root $Path 'Synthetic pinned core resource.'
            $CoreManifest.files[$Path] = (Get-FileHash (Join-Path $Root $Path)).Hash.ToLowerInvariant()
        }
        Set-InventoryFile $Root '.specify/integrations/speckit.manifest.json' ($CoreManifest | ConvertTo-Json -Depth 10)
        $Before = Get-InventoryState $Root
        $Preview = Invoke-WorkspaceFixture
        $Preview.Ready | Should -BeTrue -Because ($Preview.Blockers | ConvertTo-Json -Depth 10)
        Get-InventoryState $Root | Should -BeExactly $Before
        $CorePath = '.specify/templates/plan-template.md'
        $CoreDigest = $CoreManifest.files[$CorePath]
        $CoreManifest.files[$CorePath] = '0' * 64
        Set-InventoryFile $Root '.specify/integrations/speckit.manifest.json' ($CoreManifest | ConvertTo-Json -Depth 10)
        (Invoke-WorkspaceFixture).Ready | Should -BeFalse
        $CoreManifest.files[$CorePath] = $CoreDigest
        Set-InventoryFile $Root '.specify/integrations/speckit.manifest.json' ($CoreManifest | ConvertTo-Json -Depth 10)
        $Manifest.files['.github/skills/speckit-plan/SKILL.md'] = '0' * 64
        Set-InventoryFile $Root '.specify/integrations/copilot.manifest.json' ($Manifest | ConvertTo-Json -Depth 10)
        (Invoke-WorkspaceFixture).Ready | Should -BeFalse
    }

    It 'returns a complete ready root-only preview and preserves source and consumer bytes/modes' {
        $BeforeSource = Get-InventoryState $script:SourceRoot
        $BeforeConsumer = Get-InventoryState $script:Inputs.WorkspacePath
        $Result = Invoke-WorkspaceFixture
        $Result.Ready | Should -BeTrue -Because ($Result.Blockers | ConvertTo-Json -Depth 10)
        $Result.Contract | Should -BeExactly 'skill-workspace-install/1'
        $Result.Extensions.Count | Should -Be 1
        $Result.OptionalOffers.Count | Should -Be 2
        @($Result.OptionalOffers | Where-Object Selected).Count | Should -Be 0
        $Result.Fingerprint | Should -Match '^[0-9a-f]{64}$'
        $Result.IntendedWrites.Path | Should -Contain ".specify/skill-library-install/operations/$($Result.Fingerprint)/operation.json"
        $Result.IntendedWrites.Path | Should -Contain '.specify/extensions.yml'
        $Result.ConsumerSnapshot.ConfigurationPrediction.AddedId | Should -BeExactly 'example'
        $Result.Extensions[0].RegistryAddition.registered_skills | Should -HaveCount 0
        @($Result.IntendedWrites | Where-Object Path -Like '.github/skills/*').Count | Should -Be 0
        Get-InventoryState $script:SourceRoot | Should -BeExactly $BeforeSource
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $BeforeConsumer
    }

    It 'previews a verified packaged root without consulting a source repository' {
        $Inputs = Set-WorkspaceLibraryFixture -Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $Before = Get-InventoryState $script:Inputs.WorkspacePath
        $Result = Invoke-SkillWorkspaceInstall @Inputs
        $Result.Ready | Should -BeTrue -Because ($Result.Blockers | ConvertTo-Json -Depth 10)
        $Result.Selection.SourceKind | Should -BeExactly 'packaged'
        $Result.Selection.SourceRoot | Should -BeExactly ([IO.Path]::GetDirectoryName($Inputs.PackageIndexPath))
        $Result.Selection.ExtensionRoots[0].SourceCommit | Should -BeExactly $Result.Selection.RequiredInventories[0].SourceCommit
        $Result.Extensions[0].CatalogOrigins[0].Path | Should -BeExactly $Inputs.PackageIndexPath
        $Result.Fingerprint | Should -Match '^[0-9a-f]{64}$'
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'enforces the installed bootstrap catalog boundary: <RuntimeId>, <Modified>' -ForEach @(
        @{ RuntimeId = 'skill'; Modified = $false; ExpectedReady = $true }
        @{ RuntimeId = 'other'; Modified = $false; ExpectedReady = $false }
        @{ RuntimeId = 'skill'; Modified = $true; ExpectedReady = $false }
    ) {
        $Workspace = $script:Inputs.WorkspacePath
        $Descriptor = '{"schema_version":"1.0","extension":{"id":"skill","name":"skill-library","version":"1.0.0"},"requires":{"speckit_version":"==1.2.3"}}'
        Set-InventoryFile $Workspace '.specify/extensions/skill/extension.yml' $Descriptor
        $Hash = (Get-FileHash -LiteralPath (Join-Path $Workspace '.specify/extensions/skill/extension.yml')).Hash.ToLowerInvariant()
        $Registry = [ordered]@{ schema_version = '1.0'; extensions = @{ skill = @{ version = '1.0.0'; enabled = $true; manifest_hash = "sha256:$Hash" } } }
        Set-InventoryFile $Workspace '.specify/extensions/.registry' ($Registry | ConvertTo-Json -Depth 10)
        Set-InventoryFile $Workspace '.specify/extensions.yml' "installed:`n- skill`nsettings:`n  auto_execute_hooks: true`nhooks: {}`n"
        if ($Modified) { [IO.File]::AppendAllText((Join-Path $Workspace '.specify/extensions/skill/extension.yml'), ' ') }
        $Inputs = Set-WorkspaceLibraryFixture -Directory (Join-Path $Workspace ".specify/extensions/$RuntimeId/library")
        $Before = Get-InventoryState $Workspace
        $Result = Invoke-SkillWorkspaceInstall @Inputs
        $Result.Ready | Should -Be $ExpectedReady -Because ($Result.Blockers | ConvertTo-Json -Depth 10)
        Get-InventoryState $Workspace | Should -BeExactly $Before
    }

    It 'accepts only typed structured library requests: <Fault>' -ForEach @(
        @{ Fault = 'valid' }, @{ Fault = 'unknown-field' }, @{ Fault = 'string-apply' }
    ) {
        $Inputs = Set-WorkspaceLibraryFixture -Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $Request = @{} + $Inputs
        $Request.Apply = $false
        $Request.OptionalSelection = @()
        if ($Fault -eq 'unknown-field') { $Request.Force = $true }
        if ($Fault -eq 'string-apply') { $Request.Apply = 'false' }
        $Before = Get-InventoryState $Inputs.WorkspacePath
        $Process = Invoke-LibraryProcess -Executable (Get-Process -Id $PID).Path -Arguments @(
            '-NoLogo', '-NoProfile', '-File', $script:WorkspaceScript, '-LibraryRequest', '-Json'
        ) -InputBytes ([Text.Encoding]::UTF8.GetBytes(($Request | ConvertTo-Json -Depth 20 -Compress)))
        if ($Fault -eq 'valid') {
            $Process.ExitCode | Should -Be 0 -Because $Process.Error
            $Result = [Text.Encoding]::UTF8.GetString($Process.Bytes) | ConvertFrom-Json -Depth 100
            $Result.Mode | Should -BeExactly 'preview'
            $Result.Ready | Should -BeTrue
            $Result.Selection.SourceKind | Should -BeExactly 'packaged'
        }
        else { $Process.ExitCode | Should -Not -Be 0 }
        Get-InventoryState $Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'arms installer/network/extraction/write/declined spies and observes no invocation' {
        $Result = Invoke-ArmedWorkspaceProbe
        $Result.Status | Should -BeExactly 'Inspected'
        foreach ($Property in $Result.Armed.PSObject.Properties) { $Property.Value | Should -Be 1 -Because "$($Property.Name) tripwire must fire before checking zero calls" }
        foreach ($Property in $Result.Spies.PSObject.Properties) { $Property.Value | Should -Be 0 -Because $Property.Name }
    }

    It 'blocks stale apply approval and invalid optional keys without mutation' {
        $Before = Get-InventoryState $script:Inputs.WorkspacePath
        (Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = ('0' * 64) }).State | Should -BeExactly 'Blocked'
        $Result = Invoke-WorkspaceFixture @{ OptionalSelection = @('example/unknown') }
        $Result.Ready | Should -BeFalse
        $Result.Blockers.Code | Should -Contain 'Selection'
        $Result.Fingerprint | Should -BeNullOrEmpty
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'refuses a preview approval token' {
        $Result = Invoke-WorkspaceFixture @{ ReviewedFingerprint = ('0' * 64) }
        $Result.Blockers.Code | Should -Contain 'ApprovalMismatch'
        $Result.Fingerprint | Should -BeNullOrEmpty
    }

    It 'refuses root apply without explicit lowercase matching approval before reservation' {
        $Before = Get-InventoryState $script:Inputs.WorkspacePath
        foreach ($Approval in @('', ('0' * 64), ('A' * 64))) {
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Approval }
            $Result.State | Should -BeExactly 'Blocked'
            $Result.Blockers.Code | Should -Contain 'ApprovalMismatch'
            $Result.MutationBegan | Should -BeFalse
        }
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'refuses unresolved state introduced after a ready approval before reservation' {
        $Preview = Invoke-WorkspaceFixture
        $Preview.Ready | Should -BeTrue
        Set-InventoryFile $script:Inputs.WorkspacePath '.specify/skill-library-install/lock' '{"unresolved":true}'
        $Before = Get-InventoryState $script:Inputs.WorkspacePath
        $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
        $Result.State | Should -BeExactly 'Blocked'
        $Result.Blockers.Code | Should -Contain 'OperationState'
        $Result.MutationBegan | Should -BeFalse
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'refuses stale artifact approval without adopting or rewriting local input' {
        $Preview = Invoke-WorkspaceFixture
        [IO.File]::AppendAllText($script:Inputs.CatalogPath[0], "`n")
        $Before = Get-InventoryState $script:Inputs.WorkspacePath
        $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
        $Result.Blockers.Code | Should -Contain 'ApprovalMismatch'
        $Result.MutationBegan | Should -BeFalse
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'projects one selected peer with independent roots and inactive nested offers' {
        $Selection = Get-SkillCommittedSelection -RepoRoot $script:Inputs.RepoRoot -SkillName example -OptionalSelection @('example/peer') -PythonPath $script:Inputs.PythonPath
        $Selection.OptionalSelection | Should -Be @('example/peer')
        $Selection.ExtensionRoots.Id | Should -Be @('example', 'peer')
        @($Selection.OptionalOffers | Where-Object TargetId -CEQ 'nested') | Should -HaveCount 1
        @($Selection.OptionalOffers | Where-Object TargetId -CEQ 'nested')[0].Selected | Should -BeFalse
        @($Selection.OptionalOffers | Where-Object Selected).TargetId | Should -BeExactly 'peer'
        @($Selection.OptionalOffers | Where-Object Selected)[0].Reason | Should -BeExactly 'Related synthetic guidance.'
        $Selection.ActiveComponents.Id | Should -Contain 'shared'
        $Selection.ActiveComponents.Id | Should -Not -Contain 'nested'
        $Selection.ActiveComponents.Id | Should -Not -Contain 'declined'
    }

    Context 'Explicit optional workspace selection' {
        BeforeEach {
            $PeerArtifacts = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            Set-WorkspaceArtifact $script:SourceRoot $PeerArtifacts -SkillName peer
            $script:Inputs.CatalogPath += Join-Path $PeerArtifacts 'catalog.json'
            $script:Inputs.ArtifactDirectory += $PeerArtifacts
            $script:ApplyFault = ''
            Mock Invoke-WorkspaceBridge {
                $Request.SyntheticPeerFault = $true
                Invoke-SyntheticWorkspaceApply -Request $Request -PythonPath $PythonPath -ScratchPath $ScratchPath
            } -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'previews one optional peer separately with unchanged root bytes and shared ownership' {
            $RootPreview = Invoke-WorkspaceFixture
            $Before = Get-InventoryState $script:Inputs.WorkspacePath
            $Selected = Invoke-WorkspaceFixture @{ OptionalSelection = @('example/peer') }
            $Selected.Ready | Should -BeTrue -Because ($Selected.Blockers | ConvertTo-Json -Depth 10)
            $Selected.Extensions.RootId | Should -Be @('example', 'peer')
            $Selected.Fingerprint | Should -Not -BeExactly $RootPreview.Fingerprint
            $Selected.Extensions[0].Archive.Sha256 | Should -BeExactly $RootPreview.Extensions[0].Archive.Sha256
            $Selected.Selection.RequiredInventories | Should -HaveCount 2
            $Selected.Selection.RequiredInventories[0].Inventory.Components.Id | Should -Not -Contain 'peer'
            $Selected.Selection.RequiredInventories[1].Inventory.Components.Id | Should -Not -Contain 'nested'
            @($Selected.OptionalOffers | Where-Object Selected).TargetId | Should -BeExactly 'peer'
            @($Selected.OptionalOffers | Where-Object TargetId -CEQ 'nested')[0].Selected | Should -BeFalse
            @($Selected.Overlaps | Where-Object SourcePath -CEQ 'LICENSE')[0].ExtensionIds | Should -Be @('example', 'peer')
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
            $Probe = Invoke-ArmedWorkspaceProbe -OptionalSelection @('example/peer')
            $Probe.Status | Should -BeExactly 'Inspected'
            foreach ($Property in $Probe.Armed.PSObject.Properties) { $Property.Value | Should -Be 1 }
            foreach ($Property in $Probe.Spies.PSObject.Properties) { $Property.Value | Should -Be 0 }
        }

        It 'refuses a root-only approval after an optional peer is selected' {
            $RootPreview = Invoke-WorkspaceFixture
            $RootPreview.Ready | Should -BeTrue
            $Before = Get-InventoryState $script:Inputs.WorkspacePath
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; OptionalSelection = @('example/peer'); ReviewedFingerprint = $RootPreview.Fingerprint }
            $Result.Blockers.Code | Should -Contain 'ApprovalMismatch'
            $Result.MutationBegan | Should -BeFalse
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
            Should -Invoke Invoke-WorkspaceBridge -Times 0 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'installs one optional peer as a separate verified extension and leaves nested choices off' {
            $Preview = Invoke-WorkspaceFixture @{ OptionalSelection = @('example/peer') }
            $Preview.Ready | Should -BeTrue -Because ($Preview.Blockers | ConvertTo-Json -Depth 10)
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; OptionalSelection = @('example/peer'); ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly 'Completed' -Because ($Result | ConvertTo-Json -Depth 8)
            $Result.CompletedExtensions.RootId | Should -Be @('example', 'peer')
            $Result.PendingExtensions | Should -HaveCount 0
            foreach ($Identity in @('example', 'peer')) {
                $Notice = Join-Path $script:Inputs.WorkspacePath ".specify/extensions/$Identity/resources/library/LICENSE"
                (Get-FileHash $Notice).Hash.ToLowerInvariant() | Should -BeExactly @($Preview.Extensions | Where-Object RootId -CEQ $Identity)[0].Members.Where({ $_.MemberPath -ceq 'resources/library/LICENSE' })[0].Sha256
            }
            foreach ($Identity in @('nested', 'declined')) { Test-Path (Join-Path $script:Inputs.WorkspacePath ".specify/extensions/$Identity") | Should -BeFalse }
            $Copies = @($Result.ObservedPaths | Where-Object { $_.Path -in @('.specify/extensions/example/resources/library/.github/skills/shared/SKILL.md', '.specify/extensions/peer/resources/library/.github/skills/shared/SKILL.md') })
            $Copies | Should -HaveCount 2
            $Copies[0].Sha256 | Should -BeExactly $Copies[1].Sha256
            $Copies[0].Inode | Should -Not -Be $Copies[1].Inode
            Should -Invoke Invoke-WorkspaceBridge -Times 2 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'rejects explicit optional <Kind> keys without mutation' -ForEach @(
            @{ Kind = 'duplicate'; Keys = @('example/peer', 'example/peer') },
            @{ Kind = 'unknown'; Keys = @('example/unknown') },
            @{ Kind = 'inactive'; Keys = @('peer/nested') }
        ) {
            $Before = Get-InventoryState $script:Inputs.WorkspacePath
            $Preview = Invoke-WorkspaceFixture @{ OptionalSelection = $Keys }
            $Preview.Ready | Should -BeFalse
            $Preview.Blockers.Code | Should -Contain 'Selection'
            $Preview.Fingerprint | Should -BeNullOrEmpty
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
        }

        It 'blocks missing selected peer artifacts without rebuilding or invoking the installer' {
            [IO.File]::Delete((Join-Path $script:Inputs.ArtifactDirectory[1] 'peer-1.0.0.zip'))
            $Before = Get-InventoryState $script:Inputs.WorkspacePath
            $Preview = Invoke-WorkspaceFixture @{ OptionalSelection = @('example/peer') }
            $Preview.Blockers.Code | Should -Contain 'Artifact'
            $Preview.Ready | Should -BeFalse
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
            Should -Invoke Invoke-WorkspaceBridge -Times 0 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'retains the root after optional peer <Fault> and blocks retry' -ForEach @(
            @{ Fault = 'notice'; Outcome = 'Failed'; State = 'Failed' },
            @{ Fault = 'constructor'; Outcome = 'Unknown'; State = 'Unknown' },
            @{ Fault = 'copy'; Outcome = 'Unknown'; State = 'Cancelled' }
        ) {
            $script:ApplyFault = $Fault
            $Preview = Invoke-WorkspaceFixture @{ OptionalSelection = @('example/peer') }
            $Preview.Ready | Should -BeTrue
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; OptionalSelection = @('example/peer'); ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly $State
            $Result.CompletedExtensions.RootId | Should -BeExactly 'example'
            $Unverified = @($Result.FailedExtensions) + @($Result.UnknownExtensions)
            $Unverified | Should -HaveCount 1
            $Unverified[0].RootId | Should -BeExactly 'peer'
            $Unverified[0].State | Should -BeExactly $Outcome
            $BeforeRetry = Get-InventoryState $script:Inputs.WorkspacePath
            (Invoke-WorkspaceFixture @{ Apply = $true; OptionalSelection = @('example/peer'); ReviewedFingerprint = $Preview.Fingerprint }).Blockers.Code | Should -Contain 'OperationState'
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $BeforeRetry
            Should -Invoke Invoke-WorkspaceBridge -Times 2 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'revalidates earlier verified bytes and next targets after <Drift> drift' -ForEach @(
            @{ Drift = 'earlier'; Path = '.specify/extensions/example/resources/library/LICENSE' },
            @{ Drift = 'next'; Path = '.specify/extensions/peer/caller.txt' }
        ) {
            $script:DriftPath = $Path
            Mock Invoke-WorkspaceBridge {
                Set-InventoryFile $script:Inputs.WorkspacePath $script:DriftPath 'Preserve intervening caller changes.'
                & $script:RealBridge -PythonPath $PythonPath -Request $Request
            } -ParameterFilter { $Request.Action -ceq 'validate-reservation' -and $Request.ContainsKey('StepIndex') -and $Request.StepIndex -eq 1 }
            $Preview = Invoke-WorkspaceFixture @{ OptionalSelection = @('example/peer') }
            $Preview.Ready | Should -BeTrue
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; OptionalSelection = @('example/peer'); ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -Not -BeExactly 'Completed'
            $Result.CompletedExtensions.RootId | Should -BeExactly 'example'
            $Result.PendingExtensions.RootId | Should -BeExactly 'peer'
            $Result.Blockers.Code | Should -Contain 'ApprovalMismatch'
            [IO.File]::ReadAllText((Join-Path $script:Inputs.WorkspacePath $Path)) | Should -BeExactly 'Preserve intervening caller changes.'
            Should -Invoke Invoke-WorkspaceBridge -Times 1 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }
    }

    It 'deduplicates selected targets while preserving every declared reason and required overlap' {
        $Root = New-WorkspaceFixture
        Set-InventorySkill $Root example @{
            required = @(@{ id = 'shared'; version = '1.0.0' }, @{ id = 'other'; version = '1.0.0' })
            optional = @(@{ id = 'peer'; version = '1.0.0'; selectionKey = 'peer'; reason = 'First peer reason.' })
        }
        Set-InventorySkill $Root other @{
            optional = @(
                @{ id = 'peer'; version = '1.0.0'; selectionKey = 'again'; reason = 'Second peer reason.' },
                @{ id = 'shared'; version = '1.0.0'; selectionKey = 'shared'; reason = 'Separate required overlap.' }
            )
        }
        [void](Save-InventoryFixture $Root)
        $Selection = Get-SkillCommittedSelection -RepoRoot $Root -SkillName example -OptionalSelection @('other/shared', 'example/peer', 'other/again') -PythonPath $script:Inputs.PythonPath
        $Selection.ExtensionRoots.Id | Should -Be @('example', 'peer', 'shared')
        $Selection.OptionalSelection | Should -Be @('example/peer', 'other/again', 'other/shared')
        @($Selection.OptionalOffers | Where-Object Selected) | Should -HaveCount 3
        @($Selection.OptionalOffers | Where-Object Selected).Reason | Should -Contain 'First peer reason.'
        @($Selection.OptionalOffers | Where-Object Selected).Reason | Should -Contain 'Second peer reason.'
        @($Selection.ActiveComponents | Where-Object Id -CEQ 'shared')[0].Reasons.Kind | Should -Contain 'required'
        @($Selection.ActiveComponents | Where-Object Id -CEQ 'shared')[0].Reasons.Kind | Should -Contain 'optional'
    }

    It 'enforces the sixteen extension root limit after distinct target selection' {
        $Root = New-WorkspaceFixture
        $Offers = @(
            foreach ($Number in 1..16) {
                $Identity = 'choice' + $Number.ToString('00')
                Set-InventorySkill $Root $Identity
                @{ id = $Identity; version = '1.0.0'; selectionKey = $Identity; reason = 'Synthetic bounded choice.' }
            }
        )
        Set-InventorySkill $Root example @{ optional = $Offers }
        [void](Save-InventoryFixture $Root)
        $Keys = @($Offers | ForEach-Object { "example/$($_.selectionKey)" })
        $Allowed = Get-SkillCommittedSelection -RepoRoot $Root -SkillName example -OptionalSelection $Keys[0..14] -PythonPath $script:Inputs.PythonPath
        $Allowed.ExtensionRoots | Should -HaveCount 16
        { Get-SkillCommittedSelection -RepoRoot $Root -SkillName example -OptionalSelection $Keys -PythonPath $script:Inputs.PythonPath } | Should -Throw
    }

    Context 'Private ordered apply boundaries' {
        It 'stops cancellation at <Boundary> without invoking the installer' -ForEach @(
            @{ Boundary = 'Prepared'; Outcome = 'Pending'; Durable = 'Prepared'; Validations = 0 },
            @{ Boundary = 'validated'; Outcome = 'Pending'; Durable = 'Prepared'; Validations = 1 },
            @{ Boundary = 'Attempting'; Outcome = 'Unknown'; Durable = 'Attempting'; Validations = 1 }
        ) {
            $Cancellation = [Threading.CancellationTokenSource]::new()
            $script:BoundaryCancellation = $Cancellation
            $script:CancelBoundary = $Boundary
            $script:BoundaryValidations = 0
            $State = [pscustomobject]@{
                ReceiptHash = 'prepared'; Cancelled = $false
                Extensions = @([pscustomobject]@{ RootId = 'first'; State = 'Pending' })
            }
            $Result = New-WorkspaceApplyResult
            $Result.LastDurableStep = 'Prepared'
            Mock Write-WorkspaceOperationReceipt {
                $script:BoundaryCancellation.Cancel()
                return 'attempting'
            }
            Mock Invoke-WorkspaceBridge { throw 'Synthetic installer must not run.' }
            $Validate = {
                $script:BoundaryValidations++
                if ($script:CancelBoundary -ceq 'validated') { $script:BoundaryCancellation.Cancel() }
                return [pscustomobject]@{ Status = 'Inspected'; Result = @{ Paths = @() }; Blockers = @() }
            }
            try {
                if ($Boundary -ceq 'Prepared') { $Cancellation.Cancel() }
                { Invoke-WorkspaceOrderedApply -Context @{ OperationPath = $TestDrive } -Result $Result -State $State -ValidateStep $Validate -InstallStep { Invoke-WorkspaceBridge } -CancellationToken $Cancellation.Token } | Should -Throw
                $State.Extensions[0].State | Should -BeExactly $Outcome
                $State.Cancelled | Should -BeTrue
                $Result.LastDurableStep | Should -BeExactly $Durable
                $script:BoundaryValidations | Should -Be $Validations
                Should -Invoke Invoke-WorkspaceBridge -Times 0 -Exactly
            }
            finally { $Cancellation.Dispose() }
        }

        It 'retains verified earlier entries and pending remainder on <Boundary>' -ForEach @(
            @{ Boundary = 'failure'; Calls = 2; Second = 'Failed' },
            @{ Boundary = 'unknown'; Calls = 2; Second = 'Unknown' },
            @{ Boundary = 'cancel'; Calls = 1; Second = 'Pending' },
            @{ Boundary = 'drift'; Calls = 1; Second = 'Pending' },
            @{ Boundary = 'intent'; Calls = 1; Second = 'Pending' }
        ) {
            $script:OrderedBoundary = $Boundary
            $script:OrderedCalls = 0
            $script:OrderedValidations = 0
            $script:OrderedReceipts = [Collections.Generic.List[object]]::new()
            $Cancellation = [Threading.CancellationTokenSource]::new()
            $State = [pscustomobject]@{
                ReceiptHash = 'prepared'; Cancelled = $false
                Extensions = @('first', 'second', 'third' | ForEach-Object { [pscustomobject]@{ RootId = $_; State = 'Pending' } })
            }
            $Result = New-WorkspaceApplyResult
            $Result.LastDurableStep = 'Prepared'
            $Context = [pscustomobject]@{ OperationPath = $TestDrive }
            Mock Write-WorkspaceOperationReceipt {
                if ($script:OrderedBoundary -ceq 'intent' -and $Extensions[1].State -ceq 'Attempting') { throw 'Synthetic second intent failure.' }
                $script:OrderedReceipts.Add(($Extensions | ConvertTo-Json -Compress))
                return "receipt-$($script:OrderedReceipts.Count)"
            }
            $Validate = {
                param($Index, $Entries, $Observed)
                $script:OrderedValidations++
                if ($Index -gt 0) {
                    $Entries[0].State | Should -BeExactly 'Verified'
                    $Observed[0].Sha256 | Should -BeExactly (Get-FileHash (Join-Path $TestDrive 'first.txt')).Hash.ToLowerInvariant()
                    if (Test-Path (Join-Path $TestDrive 'second.txt')) { throw 'Synthetic next-target precondition changed.' }
                }
                return [pscustomobject]@{ Status = 'Inspected'; Result = @{ Paths = @($Observed) }; Blockers = @() }
            }
            $Install = {
                param($Index)
                $script:OrderedCalls++
                $Intent = $script:OrderedReceipts[-1] | ConvertFrom-Json
                $Intent[$Index].State | Should -BeExactly 'Attempting'
                if ($Index -eq 0) {
                    [IO.File]::WriteAllText((Join-Path $TestDrive 'first.txt'), 'Verified synthetic bytes.')
                    if ($script:OrderedBoundary -ceq 'drift') { [IO.File]::WriteAllText((Join-Path $TestDrive 'second.txt'), 'Preserve caller drift.') }
                    if ($script:OrderedBoundary -ceq 'cancel') { $Cancellation.Cancel() }
                    return [pscustomobject]@{ Status = 'Applied'; Blockers = @(); Result = @{
                        Outcome = 'Verified'; Called = $true
                        ObservedPaths = @(@{ Path = 'first.txt'; Presence = 'present'; Sha256 = (Get-FileHash (Join-Path $TestDrive 'first.txt')).Hash.ToLowerInvariant() })
                    } }
                }
                return [pscustomobject]@{ Status = 'Blocked'; Blockers = @(); Result = @{
                    Outcome = $(if ($script:OrderedBoundary -ceq 'failure') { 'Failed' } else { 'Unknown' })
                    Called = $true; ObservedPaths = @($Result.ObservedPaths)
                } }
            }
            try {
                { Invoke-WorkspaceOrderedApply -Context $Context -Result $Result -State $State -ValidateStep $Validate -InstallStep $Install -CancellationToken $Cancellation.Token } | Should -Throw
                $State.Extensions.State | Should -Be @('Verified', $Second, 'Pending')
                $script:OrderedCalls | Should -Be $Calls
                $script:OrderedValidations | Should -Be $(if ($Boundary -ceq 'cancel') { 1 } else { 2 })
                [IO.File]::ReadAllText((Join-Path $TestDrive 'first.txt')) | Should -BeExactly 'Verified synthetic bytes.'
                $State.Cancelled | Should -Be ($Boundary -ceq 'cancel')
                $Result.LastDurableStep | Should -BeExactly $(if ($Calls -eq 2) { 'Attempting' } else { 'Verified' })
            }
            finally { $Cancellation.Dispose() }
        }
    }

    Context 'Synthetic approved root apply' {
        BeforeEach {
            $script:ApplyFault = ''
            Mock Invoke-WorkspaceBridge {
                Invoke-SyntheticWorkspaceApply -Request $Request -PythonPath $PythonPath -ScratchPath $ScratchPath
            } -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'applies packaged releases only with an exact version and matching approval: <Approval>' -ForEach @(
            @{ Approval = 'missing-version'; ExpectedState = 'Blocked' }
            @{ Approval = 'stale'; ExpectedState = 'Blocked' }
            @{ Approval = 'matching'; ExpectedState = 'Completed' }
        ) {
            $Inputs = Set-WorkspaceLibraryFixture -Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $Preview = Invoke-SkillWorkspaceInstall @Inputs
            $Preview.Ready | Should -BeTrue -Because ($Preview.Blockers | ConvertTo-Json -Depth 10)
            if ($Approval -ne 'missing-version') { $Inputs.PackageVersion = $Preview.Selection.Root.Version }
            $Fingerprint = if ($Approval -eq 'stale') { '0' * 64 } else { $Preview.Fingerprint }
            $Before = Get-InventoryState $Inputs.WorkspacePath
            $Result = Invoke-SkillWorkspaceInstall @Inputs -Apply -ReviewedFingerprint $Fingerprint
            $Result.State | Should -BeExactly $ExpectedState -Because ($Result | ConvertTo-Json -Depth 20)
            if ($ExpectedState -eq 'Blocked') {
                Get-InventoryState $Inputs.WorkspacePath | Should -BeExactly $Before
                Should -Invoke Invoke-WorkspaceBridge -Times 0 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
            }
            else {
                $Result.CompletedExtensions.RootId | Should -BeExactly 'example'
                $Result.LastDurableStep | Should -BeExactly 'Completed'
                $Receipt = [IO.File]::ReadAllText((Join-Path $Result.OperationPath 'operation.json')) | ConvertFrom-Json -Depth 100
                $Receipt.ApprovedInputs.Selection.SourceKind | Should -BeExactly 'packaged'
                $Receipt.Extensions[0].State | Should -BeExactly 'Verified'
                Test-Path (Join-Path $Inputs.WorkspacePath '.specify/skill-library-install/lock') | Should -BeFalse
                Should -Invoke Invoke-WorkspaceBridge -Times 1 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
            }
        }

        It 'flushes intent before the same-stream pinned call and completes only after exact postchecks' {
            $SourceBefore = Get-InventoryState $script:Inputs.RepoRoot
            $EnvironmentBefore = $env:TMPDIR
            $Seed = @'
import json, sys, yaml
from pathlib import Path
root = Path(sys.argv[1])
extensions = root / ".specify/extensions"
extensions.mkdir()
(extensions / ".registry").write_text(json.dumps({"schema_version":"1.0", "extensions":{"other":{"version":"9.9.9", "synthetic":True}}}, indent=2))
(root / ".specify/extensions.yml").write_text(yaml.dump({"installed":["other"], "settings":{"auto_execute_hooks":False}, "hooks":{}}, default_flow_style=False, sort_keys=False, allow_unicode=True))
'@
            $SeedResult = Invoke-LibraryProcess -Executable $script:Inputs.PythonPath -Arguments @('-I', '-B', '-c', $Seed, $script:Inputs.WorkspacePath)
            $SeedResult.ExitCode | Should -Be 0 -Because $SeedResult.Error
            Set-InventoryFile $script:Inputs.WorkspacePath '.specify/extensions/other/preserve.txt' 'Preserve unrelated synthetic extension.'
            Set-InventoryFile $script:Inputs.WorkspacePath '.github/skills/unrelated/SKILL.md' 'Preserve unrelated synthetic command.'
            Set-InventoryFile $script:Inputs.WorkspacePath '.github/skills/speckit-example-load/SKILL.md' 'Preserve unrelated pre-existing name.'
            $Preview = Invoke-WorkspaceFixture
            $Preview.Ready | Should -BeTrue
            $Preview.Extensions[0].Members[0].Sha256 = '0' * 64
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly 'Completed' -Because ($Result | ConvertTo-Json -Depth 20)
            $Result.CompletedExtensions.RootId | Should -BeExactly 'example'
            $Result.FailedExtensions | Should -HaveCount 0
            $Result.UnknownExtensions | Should -HaveCount 0
            $Result.PendingExtensions | Should -HaveCount 0
            $Result.LastDurableStep | Should -BeExactly 'Completed'
            Get-WorkspaceExitCode $Result | Should -Be 0
            $Receipt = [IO.File]::ReadAllText((Join-Path $Result.OperationPath 'operation.json')) | ConvertFrom-Json -Depth 100
            $Receipt.State | Should -BeExactly 'Completed'
            $Receipt.Extensions[0].State | Should -BeExactly 'Verified'
            $Receipt.ObservedPaths.Count | Should -BeGreaterThan 0
            $Receipt.ApprovedInputs.Extensions[0].Members[0].Sha256 | Should -Not -BeExactly ('0' * 64)
            [IO.File]::ReadAllText((Join-Path $script:Inputs.WorkspacePath '.specify/extensions/other/preserve.txt')) | Should -BeExactly 'Preserve unrelated synthetic extension.'
            [IO.File]::ReadAllText((Join-Path $script:Inputs.WorkspacePath '.github/skills/unrelated/SKILL.md')) | Should -BeExactly 'Preserve unrelated synthetic command.'
            [IO.File]::ReadAllText((Join-Path $script:Inputs.WorkspacePath '.github/skills/speckit-example-load/SKILL.md')) | Should -BeExactly 'Preserve unrelated pre-existing name.'
            Test-Path (Join-Path $script:Inputs.WorkspacePath '.specify/skill-library-install/lock') | Should -BeFalse
            Test-Path (Join-Path $Result.OperationPath 'scratch') -PathType Container | Should -BeTrue
            @(Get-ChildItem (Join-Path $Result.OperationPath 'scratch') -Force).Count | Should -Be 0
            $env:TMPDIR | Should -BeExactly $EnvironmentBefore
            Get-InventoryState $script:Inputs.RepoRoot | Should -BeExactly $SourceBefore
            Should -Invoke Invoke-WorkspaceBridge -Times 1 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
            $BeforeRetry = Get-InventoryState $script:Inputs.WorkspacePath
            $Retry = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Retry.State | Should -BeExactly 'Blocked'
            $Retry.Blockers.Code | Should -Contain 'Ownership'
            $Retry.Blockers.Code | Should -Not -Contain 'OperationState'
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $BeforeRetry
        }

        It 'preserves an existing <Conflict> target and refuses before any apply call' -ForEach @(
            @{ Conflict = 'same-version' }, @{ Conflict = 'local-edit' }, @{ Conflict = 'orphan' },
            @{ Conflict = 'command-only' }, @{ Conflict = 'registry-only' }
        ) {
            $Preview = Invoke-WorkspaceFixture
            $Preview.Ready | Should -BeTrue
            $Root = $script:Inputs.WorkspacePath
            switch ($Conflict) {
                'same-version' { Set-InventoryFile $Root '.specify/extensions/example/extension.yml' 'extension: {id: example, version: 1.0.0}' }
                'local-edit' {
                    Set-InventoryFile $Root '.specify/extensions/example/resources/library/SKILL.md' 'Preserve caller edits.'
                    [IO.File]::SetUnixFileMode((Join-Path $Root '.specify/extensions/example/resources/library/SKILL.md'), [IO.UnixFileMode]384)
                }
                'orphan' { Set-InventoryFile $Root '.specify/extensions/example/orphan.bin' -Bytes ([byte[]]@(255, 0, 128)) }
                'command-only' { Set-InventoryFile $Root '.github/skills/speckit-example-load/SKILL.md' 'Preserve caller command.' }
                'registry-only' { Set-InventoryFile $Root '.specify/extensions/.registry' '{"schema_version":"1.0","extensions":{"example":{"version":"1.0.0"}}}' }
            }
            $Before = Get-InventoryState $Root
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly 'Blocked'
            $Result.MutationBegan | Should -BeFalse
            Get-InventoryState $Root | Should -BeExactly $Before
            Test-Path (Join-Path $Root '.specify/skill-library-install') | Should -BeFalse
            Should -Invoke Invoke-WorkspaceBridge -Times 0 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'retains a foreign same-byte lock and verified result after completion evidence' {
            $Preview = Invoke-WorkspaceFixture
            Mock Remove-WorkspaceOperationLock {
                $Lock = Join-Path $Context.WorkspacePath '.specify/skill-library-install/lock'
                $Bytes = [IO.File]::ReadAllBytes($Lock)
                [IO.File]::Move($Lock, "$Lock.original")
                [IO.File]::WriteAllBytes($Lock, $Bytes)
                [IO.File]::SetUnixFileMode($Lock, [IO.UnixFileMode]384)
                & $script:ReleaseLock -Context $Context
            }
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly 'Unknown'
            $Result.CompletedExtensions | Should -HaveCount 1
            $Result.UnknownExtensions | Should -HaveCount 0
            $Result.LastDurableStep | Should -BeExactly 'Completed'
            Get-WorkspaceExitCode $Result | Should -Be 3
            $Receipt = [IO.File]::ReadAllText((Join-Path $Result.OperationPath 'operation.json')) | ConvertFrom-Json
            $Receipt.State | Should -BeExactly 'Completed'
            $BeforeRetry = Get-InventoryState $script:Inputs.WorkspacePath
            (Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }).Blockers.Code | Should -Contain 'OperationState'
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $BeforeRetry
            Should -Invoke Invoke-WorkspaceBridge -Times 1 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'refuses a corrupted selected artifact after approval without creating operation evidence' {
            $Preview = Invoke-WorkspaceFixture
            Set-WorkspaceZipFault notice
            $Before = Get-InventoryState $script:Inputs.WorkspacePath
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly 'Blocked'
            $Result.Blockers.Code | Should -Contain 'Artifact'
            $Result.MutationBegan | Should -BeFalse
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
            Should -Invoke Invoke-WorkspaceBridge -Times 0 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'stops after reserved-state drift and reports retained evidence before any installer call' {
            $Preview = Invoke-WorkspaceFixture
            Mock New-WorkspaceOperationEvidence {
                $Operation = & $script:ReserveEvidence -Context $Context
                Set-InventoryFile $Context.WorkspacePath '.specify/init-options.json' '{"ai":"copilot","ai_skills":true,"script":"synthetic-drift"}'
                return $Operation
            }
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly 'Failed'
            $Result.Blockers.Code | Should -Contain 'ApprovalMismatch'
            $Result.MutationBegan | Should -BeTrue
            $Result.PendingExtensions | Should -HaveCount 1
            $Result.LastDurableStep | Should -BeExactly 'Failed'
            Test-Path (Join-Path $Result.OperationPath 'operation.json') | Should -BeTrue
            Test-Path (Join-Path $script:Inputs.WorkspacePath '.specify/skill-library-install/lock') | Should -BeTrue
            Test-Path (Join-Path $script:Inputs.WorkspacePath '.specify/extensions/example') | Should -BeFalse
            Should -Invoke Invoke-WorkspaceBridge -Times 0 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'keeps an unstarted extension pending when intent and outcome receipts cannot be flushed' {
            $Preview = Invoke-WorkspaceFixture
            Mock Write-WorkspaceOperationReceipt { throw 'Synthetic receipt failure.' } -ParameterFilter {
                $LastDurableStep -in @('Attempting', 'Failed', 'Unknown')
            }
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly 'Failed'
            $Result.PendingExtensions | Should -HaveCount 1
            $Result.UnknownExtensions | Should -HaveCount 0
            $Result.LastDurableStep | Should -BeExactly 'Prepared'
            $Receipt = [IO.File]::ReadAllText((Join-Path $Result.OperationPath 'operation.json')) | ConvertFrom-Json -Depth 100
            $Receipt.State | Should -BeExactly 'Prepared'
            $Receipt.Extensions[0].State | Should -BeExactly 'Pending'
            $Result.Blockers.Code | Should -Contain 'OperationState'
            Get-WorkspaceExitCode $Result | Should -Be 3
            Should -Invoke Invoke-WorkspaceBridge -Times 0 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'preserves partial observations after synthetic <Fault> and blocks retry' -ForEach @(
            @{ Fault = 'constructor'; Cancelled = $false; Payload = $false },
            @{ Fault = 'before-copy'; Cancelled = $true; Payload = $false },
            @{ Fault = 'copy'; Cancelled = $true; Payload = $true },
            @{ Fault = 'registration'; Cancelled = $true; Payload = $true },
            @{ Fault = 'kill-before-copy'; Cancelled = $false; Payload = $false },
            @{ Fault = 'kill-copy'; Cancelled = $false; Payload = $true },
            @{ Fault = 'kill-registration'; Cancelled = $false; Payload = $true },
            @{ Fault = 'kill-verified'; Cancelled = $false; Payload = $true },
            @{ Fault = 'malformed'; Cancelled = $false; Payload = $true },
            @{ Fault = 'observe'; Cancelled = $false; Payload = $true }
        ) {
            $SourceBefore = Get-InventoryState $script:Inputs.RepoRoot
            $EnvironmentBefore = $env:TMPDIR
            Set-InventoryFile $script:Inputs.WorkspacePath '.specify/scripts/preserve.txt' 'Preserve synthetic caller content.'
            $script:ApplyFault = $Fault
            $Preview = Invoke-WorkspaceFixture
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -BeExactly $(if ($Cancelled) { 'Cancelled' } else { 'Unknown' })
            $Result.UnknownExtensions | Should -HaveCount 1
            $Result.CompletedExtensions | Should -HaveCount 0
            $Result.ObservedPaths.Count | Should -BeGreaterThan 0
            if ($Payload) {
                $PayloadObservation = @($Result.ObservedPaths | Where-Object Path -CEQ '.specify/extensions/example/resources/library/LICENSE')
                $FailureSummary = $Result | Select-Object State, Blockers, LastDurableStep | ConvertTo-Json -Depth 8 -Compress
                $PayloadObservation | Should -HaveCount 1 -Because $FailureSummary
                $PayloadObservation[0].Presence | Should -BeExactly 'present' -Because $FailureSummary
            }
            if ($Fault -ceq 'observe') {
                @($Result.ObservedPaths | Where-Object Presence -CEQ 'unknown').Count | Should -BeGreaterThan 0
            }
            [IO.File]::ReadAllText((Join-Path $script:Inputs.WorkspacePath '.specify/scripts/preserve.txt')) | Should -BeExactly 'Preserve synthetic caller content.'
            $env:TMPDIR | Should -BeExactly $EnvironmentBefore
            Get-InventoryState $script:Inputs.RepoRoot | Should -BeExactly $SourceBefore
            Get-WorkspaceExitCode $Result | Should -Be 3
            Test-Path (Join-Path $script:Inputs.WorkspacePath '.specify/skill-library-install/lock') | Should -BeTrue
            $BeforeRetry = Get-InventoryState $script:Inputs.WorkspacePath
            $Retry = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Retry.Blockers.Code | Should -Contain 'OperationState'
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $BeforeRetry
            Should -Invoke Invoke-WorkspaceBridge -Times 1 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'retains the last durable <Durable> receipt after <Boundary> persistence fails' -ForEach @(
            @{ Boundary = 'Prepared'; Durable = $null; Completed = 0 },
            @{ Boundary = 'Verified'; Durable = 'Attempting'; Completed = 1 },
            @{ Boundary = 'Completed'; Durable = 'Verified'; Completed = 1 }
        ) {
            $script:ReceiptBoundary = $Boundary
            $Preview = Invoke-WorkspaceFixture
            Mock Write-WorkspaceOperationReceipt { throw 'Synthetic receipt failure.' } -ParameterFilter {
                $LastDurableStep -ceq $script:ReceiptBoundary -or $State -in @('Failed', 'Unknown', 'Cancelled')
            }
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Result.State | Should -Not -BeExactly 'Completed'
            $Result.CompletedExtensions | Should -HaveCount $Completed
            $Result.LastDurableStep | Should -BeExactly $Durable
            Get-WorkspaceExitCode $Result | Should -Be 3
            Test-Path (Join-Path $script:Inputs.WorkspacePath '.specify/skill-library-install/lock') | Should -BeTrue
            if ($Durable) {
                $Receipt = [IO.File]::ReadAllText((Join-Path $Result.OperationPath 'operation.json')) | ConvertFrom-Json -Depth 100
                $Receipt.LastDurableStep | Should -BeExactly $Durable
            }
            $BeforeRetry = Get-InventoryState $script:Inputs.WorkspacePath
            $Retry = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Retry.Blockers.Code | Should -Contain 'OperationState'
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $BeforeRetry
            Should -Invoke Invoke-WorkspaceBridge -Times $(if ($Boundary -ceq 'Prepared') { 0 } else { 1 }) -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }

        It 'rejects synthetic <Fault> after delegation and retains ambiguous runtime and evidence paths' -ForEach @(
            @{ Fault = 'notice' }, @{ Fault = 'command' }, @{ Fault = 'version' }, @{ Fault = 'registry' },
            @{ Fault = 'extra' }, @{ Fault = 'mode' }, @{ Fault = 'unrelated' }, @{ Fault = 'warning' }, @{ Fault = 'raise' }, @{ Fault = 'cancel' }
        ) {
            Set-InventoryFile $script:Inputs.WorkspacePath '.specify/scripts/preserve.txt' 'Preserve synthetic caller content.'
            $script:ApplyFault = $Fault
            $Preview = Invoke-WorkspaceFixture
            $Preview.Ready | Should -BeTrue
            $Result = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            if ($Fault -ceq 'cancel') {
                $Result.State | Should -BeExactly 'Cancelled'
                $Result.UnknownExtensions | Should -HaveCount 1
                $Result.LastDurableStep | Should -BeExactly 'Cancelled'
            }
            else { $Result.State | Should -BeIn @('Failed', 'Unknown') }
            $Result.CompletedExtensions | Should -HaveCount 0
            (@($Result.FailedExtensions) + @($Result.UnknownExtensions)).Count | Should -Be 1
            $Result.MutationBegan | Should -BeTrue
            $Result.RecoveryLocations.Count | Should -BeGreaterThan 0
            Get-WorkspaceExitCode $Result | Should -Be 3
            Test-Path (Join-Path $Result.OperationPath 'operation.json') | Should -BeTrue
            Test-Path (Join-Path $script:Inputs.WorkspacePath '.specify/extensions/example/resources/library/LICENSE') | Should -BeTrue
            Test-Path (Join-Path $script:Inputs.WorkspacePath '.specify/skill-library-install/lock') | Should -BeTrue
            $BeforeRetry = Get-InventoryState $script:Inputs.WorkspacePath
            $Retry = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Preview.Fingerprint }
            $Retry.State | Should -BeExactly 'Blocked'
            $Retry.Blockers.Code | Should -Contain 'OperationState'
            Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $BeforeRetry
            Should -Invoke Invoke-WorkspaceBridge -Times 1 -Exactly -ParameterFilter { $Request.ContainsKey('Mode') -and $Request.Mode -ceq 'apply' }
        }
    }

    It 'keeps empty and singleton collections as arrays in object and CLI JSON results' {
        $Result = Invoke-WorkspaceFixture
        $Result.Blockers | Should -HaveCount 0
        $Result.Extensions | Should -HaveCount 1
        $JsonResult = $Result | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
        $JsonResult.Blockers -is [array] | Should -BeTrue
        $JsonResult.Extensions -is [array] | Should -BeTrue
        $JsonResult.OptionalOffers -is [array] | Should -BeTrue
        $JsonResult.Selection.OptionalSelection -is [array] | Should -BeTrue
        $Cli = Invoke-LibraryProcess -Executable (Get-Process -Id $PID).Path -Arguments @(
            '-NoProfile', '-File', $script:WorkspaceScript, '-RepoRoot', $script:Inputs.RepoRoot, '-SkillName', 'example',
            '-WorkspacePath', $script:Inputs.WorkspacePath, '-CatalogPath', $script:Inputs.CatalogPath[0],
            '-ArtifactDirectory', $script:Inputs.ArtifactDirectory[0], '-PythonPath', $script:Inputs.PythonPath, '-Json'
        )
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Cli.Error | Should -BeNullOrEmpty
        $Parsed = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json -AsHashtable
        $Parsed.Ready | Should -BeTrue
        $Parsed.Extensions -is [array] | Should -BeTrue
    }

    It 'preserves committed membership despite dirty, deleted, staged and untracked source bytes' {
        $Ready = Invoke-WorkspaceFixture
        $Ready.Ready | Should -BeTrue
        $Root = $script:SourceRoot
        try {
            Set-InventoryFile $Root '.github/skills/shared/references/detail.md' 'Dirty synthetic resource.'
            [void](Invoke-InventoryGit $Root @('add', '.github/skills/shared/references/detail.md'))
            [IO.File]::Delete((Join-Path $Root 'LICENSE'))
            Set-InventoryFile $Root '.github/skills/example/untracked.md' 'Not approved content.'
            $Before = Get-InventoryState $Root
            $Result = Invoke-WorkspaceFixture
            $Result.Ready | Should -BeTrue
            $Result.Fingerprint | Should -BeExactly $Ready.Fingerprint
            Get-InventoryState $Root | Should -BeExactly $Before
        }
        finally {
            $Original = Invoke-LibraryGit -Root $Root -Arguments @('show', 'HEAD:.github/skills/shared/references/detail.md')
            Set-InventoryFile $Root '.github/skills/shared/references/detail.md' -Bytes $Original.Bytes
            [void](Invoke-InventoryGit $Root @('add', '.github/skills/shared/references/detail.md'))
            Set-InventoryFile $Root 'LICENSE' "Synthetic notice.`n"
            [IO.File]::Delete((Join-Path $Root '.github/skills/example/untracked.md'))
        }
    }

    It 'rejects exact archive evidence fault <Fault> without extraction or consumer changes' -ForEach @(
        @{ Fault = 'notice' }, @{ Fault = 'mode' }, @{ Fault = 'link' }, @{ Fault = 'duplicate-member' },
        @{ Fault = 'duplicate-json' }, @{ Fault = 'duplicate-yaml' }, @{ Fault = 'traversal' }, @{ Fault = 'extra' }, @{ Fault = 'oversize-member' }
    ) {
        Set-WorkspaceZipFault $Fault
        $Before = Get-InventoryState $script:Inputs.WorkspacePath
        $Result = Invoke-WorkspaceFixture
        $Result.Ready | Should -BeFalse
        $Result.Blockers.Code | Should -Contain 'Artifact'
        $Result.Fingerprint | Should -BeNullOrEmpty
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'binds changed raw catalog and archive bytes even when parsed membership stays equal' {
        $First = Invoke-WorkspaceFixture
        [IO.File]::AppendAllText($script:Inputs.CatalogPath[0], "`n")
        $Second = Invoke-WorkspaceFixture
        $First.Ready | Should -BeTrue
        $Second.Ready | Should -BeTrue
        $First.Fingerprint | Should -Not -BeExactly $Second.Fingerprint
        Set-WorkspaceZipFault 'raw-bytes'
        $Third = Invoke-WorkspaceFixture
        $Third.Ready | Should -BeTrue
        $Second.Fingerprint | Should -Not -BeExactly $Third.Fingerprint
    }

    It 'binds complete participating tool identities and no temporary-backed projection paths' {
        $Result = Invoke-WorkspaceFixture
        $Result.Ready | Should -BeTrue
        foreach ($Tool in @($Result.Selection.Tools) + @($Result.ConsumerSnapshot.Runtime.Tools)) {
            $Tool.Role | Should -Not -BeNullOrEmpty
            $Tool.Path | Should -Not -Match '/skill-inventory-[^/]+/'
            (Get-FileHash -LiteralPath $Tool.Path -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $Tool.Sha256
        }
        ($Result.Selection | ConvertTo-Json -Depth 100) | Should -Not -Match 'StagedPath|/skill-inventory-[^/]+/'
    }

    It 'uses stable UTF-8 ordering, numeric indexes and recursive ties for unordered evidence' {
        $Projection = @{
            Tools = @(@{ Role = 'z'; Path = '/example/Z'; Sha256 = 'a' }, @{ Role = 'A'; Path = '/example/A'; Sha256 = 'b' })
            OptionalOffers = @(@{ DeclaringId = 'example'; SelectionKey = 'same'; OptionalIndex = 10 }, @{ DeclaringId = 'example'; SelectionKey = 'same'; OptionalIndex = 2 })
            IntendedWrites = @(@{ Path = 'same'; Position = 0; Effect = 'write'; Reasons = @('z', 'A') }, @{ Path = 'same'; Position = 0; Effect = 'write'; Reasons = @('b', 'a') })
            Paths = @(@{ Path = 'same'; Sha256 = 'b' }, @{ Path = 'same'; Sha256 = 'a' })
            Reasons = @('z', 'A', 'a', [string][char]0xE9, [char]::ConvertFromUtf32(0x1F600))
            ExtensionRoots = @(@{ Position = 0; Id = 'example' })
        }
        $First = Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection $Projection
        $Other = $Projection | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
        foreach ($Key in @('Tools', 'OptionalOffers', 'IntendedWrites', 'Paths', 'Reasons')) { [array]::Reverse($Other[$Key]) }
        foreach ($Write in $Other.IntendedWrites) { [array]::Reverse($Write.Reasons) }
        (Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection $Other) | Should -BeExactly $First
        $Other.OptionalOffers[0].OptionalIndex = 11
        (Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection $Other) | Should -Not -BeExactly $First
        $Other = $Projection | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
        $Other.ExtensionRoots[0].Position = 1
        (Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection $Other) | Should -Not -BeExactly $First
        $Other = $Projection | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
        $Other.Tools[0].Sha256 = 'changed'
        (Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection $Other) | Should -Not -BeExactly $First
        { Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection @{ Unsupported = 1.5 } } | Should -Throw
        $Unicode = [string][char]0xE9
        $Golden = @{ OptionalOffers = @(@{ DeclaringId = 'example'; SelectionKey = 'same'; OptionalIndex = 10 }, @{ DeclaringId = 'example'; SelectionKey = 'same'; OptionalIndex = 2 }); Reasons = @('z', $Unicode, 'a', 'A') }
        $ExpectedJson = '{"OptionalOffers":[{"DeclaringId":"example","OptionalIndex":2,"SelectionKey":"same"},{"DeclaringId":"example","OptionalIndex":10,"SelectionKey":"same"}],"Reasons":["A","a","z","' + $Unicode + '"]}'
        $ExpectedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($ExpectedJson))).ToLowerInvariant()
        (Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection $Golden) | Should -BeExactly $ExpectedHash
        (Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection @{ Value = $null }) | Should -Not -BeExactly (Get-WorkspaceFingerprint -PythonPath $script:Inputs.PythonPath -Projection @{ Value = @() })
    }

    It 'normalizes permutations of unordered catalog and artifact arguments without changing approval' {
        $EmptyCatalog = Join-Path $TestDrive 'other-catalog.json'
        [IO.File]::WriteAllText($EmptyCatalog, '{"schema_version":"1.0","extensions":{}}')
        $OtherArtifacts = Join-Path $TestDrive 'other-artifacts'
        [void][IO.Directory]::CreateDirectory($OtherArtifacts)
        $First = Invoke-WorkspaceFixture @{ CatalogPath = @($script:Inputs.CatalogPath[0], $EmptyCatalog); ArtifactDirectory = @($script:Inputs.ArtifactDirectory[0], $OtherArtifacts) }
        $Other = Invoke-WorkspaceFixture @{ CatalogPath = @($EmptyCatalog, $script:Inputs.CatalogPath[0]); ArtifactDirectory = @($OtherArtifacts, $script:Inputs.ArtifactDirectory[0]) }
        $First.Ready | Should -BeTrue
        $Other.Ready | Should -BeTrue
        $Other.Fingerprint | Should -BeExactly $First.Fingerprint
    }

    It 'ignores ordinary Markdown links rather than activating declined graph targets' {
        $Result = Invoke-WorkspaceFixture
        $Result.Selection.ActiveComponents.Id | Should -Not -Contain 'declined'
        $Result.Extensions.RootId | Should -Not -Contain 'declined'
        $Result.Extensions[0].SourceManifest.Components.Id | Should -Not -Contain 'peer'
    }

    It 'rejects all private evidence writers without an approved apply context' {
        $Before = Get-InventoryState $script:Inputs.WorkspacePath
        { Write-WorkspaceOwnedFile -Context @{ Mode = 'preview' } -Path '/example/evidence' -Bytes ([byte[]]@(1)) } | Should -Throw
        { New-WorkspaceOperationEvidence -Context @{ Mode = 'preview' } } | Should -Throw
        { Write-WorkspaceOperationReceipt -Context @{ Mode = 'preview' } -OperationPath '/example' -State Prepared -Extensions @() } | Should -Throw
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'creates private evidence exclusively and rejects foreign same-byte replacements' {
        $Preview = Invoke-WorkspaceFixture
        $Preview.Ready | Should -BeTrue
        $Context = [pscustomobject]@{
            Mode = 'apply'; ApprovedInputs = $Preview; OperationId = $Preview.Fingerprint
            WorkspacePath = $script:Inputs.WorkspacePath; RepoRoot = $script:Inputs.RepoRoot; PythonPath = $script:Inputs.PythonPath
        }
        $Operation = New-WorkspaceOperationEvidence $Context
        $Extensions = @([pscustomobject]@{ RootId = 'example'; State = 'Pending' })
        $Digest = Write-WorkspaceOperationReceipt -Context $Context -OperationPath $Operation -State Prepared -Extensions $Extensions -LastDurableStep Prepared
        $Receipt = Join-Path $Operation 'operation.json'
        [IO.File]::GetUnixFileMode($Operation) | Should -Be ([IO.UnixFileMode]448)
        [IO.File]::GetUnixFileMode($Receipt) | Should -Be ([IO.UnixFileMode]384)
        $Extensions[0].State = 'Attempting'
        $Digest = Write-WorkspaceOperationReceipt -Context $Context -OperationPath $Operation -State Running -Extensions $Extensions -LastDurableStep Attempting -PreviousSha256 $Digest
        ([IO.File]::ReadAllText($Receipt) | ConvertFrom-Json).LastDurableStep | Should -BeExactly 'Attempting'
        $Bytes = [IO.File]::ReadAllBytes($Receipt)
        [IO.File]::Move($Receipt, "$Receipt.foreign-original")
        [IO.File]::WriteAllBytes($Receipt, $Bytes)
        [IO.File]::SetUnixFileMode($Receipt, [IO.UnixFileMode]384)
        { Write-WorkspaceOperationReceipt -Context $Context -OperationPath $Operation -State Running -Extensions $Extensions -LastDurableStep Attempting -PreviousSha256 $Digest } | Should -Throw
        [IO.File]::ReadAllBytes($Receipt) | Should -Be $Bytes
        { New-WorkspaceOperationEvidence $Context } | Should -Throw
        $Blocked = Invoke-WorkspaceFixture
        $Blocked.Ready | Should -BeFalse
        $Blocked.Blockers.Code | Should -Contain 'OperationState'
    }

    It 'refuses missing and ambiguous local <Kind> inputs' -ForEach @(@{ Kind = 'catalog' }, @{ Kind = 'artifact' }, @{ Kind = 'duplicate-catalog' }, @{ Kind = 'duplicate-artifact' }) {
        switch ($Kind) {
            'catalog' { [IO.File]::Delete($script:Inputs.CatalogPath[0]) }
            'artifact' { [IO.File]::Delete((Join-Path $script:Inputs.ArtifactDirectory[0] 'example-1.0.0.zip')) }
            'duplicate-catalog' { $script:Inputs.CatalogPath += $script:Inputs.CatalogPath[0] }
            'duplicate-artifact' { $script:Inputs.ArtifactDirectory += $script:Inputs.ArtifactDirectory[0] }
        }
        $Result = Invoke-WorkspaceFixture
        $Result.Ready | Should -BeFalse
        $Result.Fingerprint | Should -BeNullOrEmpty
        $Result.Blockers.Code | Should -Contain $(if ($Kind -match 'catalog') { 'Catalog' } else { 'Artifact' })
    }

    It 'checks aggregate focused runner result <Case>' -ForEach @(
        @{ Case = 'passed'; Aggregate = 'Passed'; Passed = 1; Total = 1; Exit = 0 },
        @{ Case = 'failed-hook'; Aggregate = 'Failed'; Passed = 1; Total = 1; Exit = 1 },
        @{ Case = 'skipped-only'; Aggregate = 'Passed'; Passed = 0; Total = 1; Exit = 1 },
        @{ Case = 'empty'; Aggregate = 'Passed'; Passed = 0; Total = 0; Exit = 1 }
    ) {
        $Root = New-InventoryFixture
        Set-InventoryFile $Root 'runner.ps1' ([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../Invoke-Tests.ps1')))
        $Module = @'
function New-PesterContainer { param([string]$Path) [pscustomobject]@{ Path = $Path } }
function Invoke-Pester {
    param($Container, $Output, [switch]$PassThru)
    [pscustomobject]@{ Result = '__AGGREGATE__'; PassedCount = __PASSED__; FailedCount = 0; TotalCount = __TOTAL__ }
}
'@
        $Module = $Module.Replace('__AGGREGATE__', $Aggregate).Replace('__PASSED__', [string]$Passed).Replace('__TOTAL__', [string]$Total)
        Set-InventoryFile $Root 'modules/Pester/5.7.1/Pester.psm1' $Module
        Set-InventoryFile $Root 'modules/Pester/5.7.1/Pester.psd1' "@{ RootModule = 'Pester.psm1'; ModuleVersion = '5.7.1'; FunctionsToExport = @('New-PesterContainer', 'Invoke-Pester') }"
        $Process = Invoke-LibraryProcess -Executable (Get-Command pwsh -CommandType Application -TotalCount 1).Source -Arguments @(
            '-NoLogo', '-NoProfile', '-File', (Join-Path $Root 'runner.ps1'), '-PythonPath', $script:Python
        ) -Environment @{ PSModulePath = (Join-Path $Root 'modules') + [IO.Path]::PathSeparator + $env:PSModulePath }
        $Process.ExitCode | Should -Be $Exit
    }

    It 'bounds approval evidence before reservation oversized=<Oversized>' -ForEach @(
        @{ Oversized = $false }, @{ Oversized = $true }
    ) {
        $Before = Get-InventoryState $script:Inputs.WorkspacePath
        $Length = if ($Oversized) { 4MB } else { 4MB - 256 }
        $Response = Invoke-WorkspaceBridge -PythonPath $script:Inputs.PythonPath -Request @{
            Action = 'fingerprint'; Projection = @{ Padding = 'x' * $Length }
        }
        if ($Oversized) {
            $Response.Status | Should -BeExactly 'Blocked'
            $Response.Blockers.Scope | Should -Contain 'approval-size'
        }
        else {
            $Response.Status | Should -BeExactly 'Inspected'
            $Response.Result.Fingerprint | Should -Match '^[0-9a-f]{64}$'
        }
        Test-Path -LiteralPath (Join-Path $script:Inputs.WorkspacePath '.specify/skill-library-install') | Should -BeFalse
        Get-InventoryState $script:Inputs.WorkspacePath | Should -BeExactly $Before
    }

    It 'refuses retained upstream rescue staging <Completed> before reservation' -ForEach @(
        @{ Completed = $false }, @{ Completed = $true }
    ) {
        $Approved = Invoke-WorkspaceFixture
        $Approved.Ready | Should -BeTrue
        $Root = $script:Inputs.WorkspacePath
        $Suffix = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('example'))).ToLowerInvariant().Substring(0, 16)
        $Relative = ".specify/extensions/.rescue-staging-$Suffix"
        Set-InventoryFile $Root "$Relative/example-config.local.yml" 'Preserve retained recovery configuration.'
        if ($Completed) { Set-InventoryFile $Root "$Relative/.rescue-complete" '' }
        $Before = Get-InventoryState $Root
        $Preview = Invoke-WorkspaceFixture
        $Preview.Ready | Should -BeFalse
        $Preview.Blockers.Code | Should -Contain 'OperationState'
        $Apply = Invoke-WorkspaceFixture @{ Apply = $true; ReviewedFingerprint = $Approved.Fingerprint }
        $Apply.Blockers.Code | Should -Contain 'OperationState'
        Test-Path -LiteralPath (Join-Path $Root '.specify/skill-library-install') | Should -BeFalse
        Get-InventoryState $Root | Should -BeExactly $Before
    }

    It 'blocks strict state/runtime refusal <Fault> and preserves evidence' -ForEach @(
        @{ Fault = 'duplicate-json' }, @{ Fault = 'duplicate-yaml' }, @{ Fault = 'wrong-integration' },
        @{ Fault = 'hooks' }, @{ Fault = 'config-comment' }, @{ Fault = 'integration-duplicate' }, @{ Fault = 'integration-external' }, @{ Fault = 'project-adapter' },
        @{ Fault = 'collateral-mode' }, @{ Fault = 'occupied' }, @{ Fault = 'linked' },
        @{ Fault = 'owner' }, @{ Fault = 'lock' }, @{ Fault = 'Prepared' }, @{ Fault = 'Running' }, @{ Fault = 'Attempting' }, @{ Fault = 'Completed-inconsistent' }, @{ Fault = 'torn' }, @{ Fault = 'missing-receipt' }
    ) {
        $Root = $script:Inputs.WorkspacePath
        $Approved = $null
        if ($Fault -in @('Prepared', 'Running', 'Attempting', 'Completed-inconsistent')) {
            $Approved = Invoke-WorkspaceFixture
            $Approved.Ready | Should -BeTrue
        }
        switch ($Fault) {
            'duplicate-json' { Set-InventoryFile $Root '.specify/init-options.json' '{"ai":"copilot","ai":"copilot","ai_skills":true}' }
            'duplicate-yaml' { Set-InventoryFile $Root '.specify/extensions.yml' "hooks: {}`nhooks: {}`n" }
            'wrong-integration' { Set-InventoryFile $Root '.specify/init-options.json' '{"ai":"external","ai_skills":true}' }
            'hooks' { Set-InventoryFile $Root '.specify/extensions.yml' 'hooks: {before: [{command: example}]}' }
            'config-comment' { Set-InventoryFile $Root '.specify/extensions.yml' "# Preserve my comment`ninstalled: []`nsettings:`n  auto_execute_hooks: true`nhooks: {}`n" }
            'integration-duplicate' { Set-InventoryFile $Root '.specify/integration.json' '{"integration":"copilot","integration":"copilot"}' }
            'integration-external' { Set-InventoryFile $Root '.specify/integration.json' '{"integration":"external"}' }
            'project-adapter' { Set-InventoryFile $Root '.specify/integrations/copilot/__init__.py' 'raise RuntimeError("Never import project code")' }
            'collateral-mode' { Set-InventoryFile $Root '.specify/scripts/example.sh' "#!/bin/sh`nexit 0`n"; [IO.File]::SetUnixFileMode((Join-Path $Root '.specify/scripts/example.sh'), [IO.UnixFileMode]420) }
            'occupied' { Set-InventoryFile $Root '.specify/extensions/example/local.txt' 'Preserve me.' }
            'linked' { [void][IO.Directory]::CreateSymbolicLink((Join-Path $Root '.specify/extensions'), $script:FixtureArtifacts) }
            default {
                $Namespace = Join-Path $Root '.specify/skill-library-install'
                [void][IO.Directory]::CreateDirectory($Namespace)
                [IO.File]::SetUnixFileMode($Namespace, [IO.UnixFileMode]448)
                if ($Fault -ne 'owner') { Set-InventoryFile $Root '.specify/skill-library-install/owner.json' '{"Contract":"skill-workspace-install/1","Kind":"operation-namespace"}'; [IO.File]::SetUnixFileMode((Join-Path $Namespace 'owner.json'), [IO.UnixFileMode]384) }
                if ($Fault -eq 'lock') { Set-InventoryFile $Root '.specify/skill-library-install/lock' '{}' }
                elseif ($Fault -notin @('owner', 'lock')) {
                    $OperationId = if ($Approved) { $Approved.Fingerprint } else { '0' * 64 }
                    $Relative = '.specify/skill-library-install/operations/' + $OperationId
                    [void][IO.Directory]::CreateDirectory((Join-Path $Root $Relative))
                    [IO.File]::SetUnixFileMode((Join-Path $Namespace 'operations'), [IO.UnixFileMode]448)
                    [IO.File]::SetUnixFileMode((Join-Path $Root $Relative), [IO.UnixFileMode]448)
                    if ($Fault -ne 'missing-receipt') {
                        $Receipt = if ($Fault -eq 'torn') { '{' } else {
                            $State = if ($Fault -eq 'Attempting') { 'Running' } elseif ($Fault -eq 'Completed-inconsistent') { 'Completed' } else { $Fault }
                            $Outcome = if ($Fault -eq 'Attempting') { 'Attempting' } elseif ($Fault -eq 'Completed-inconsistent') { 'Verified' } else { 'Pending' }
                            if ($Fault -eq 'Completed-inconsistent') { $Approved.Fingerprint = $null }
                            @{
                                Contract = 'skill-workspace-install/1'; OperationId = $OperationId; ReviewedFingerprint = $OperationId
                                ApprovedInputs = $Approved; State = $State; LastDurableStep = $State
                                Extensions = @(@{ RootId = 'example'; State = $Outcome }); IntendedPaths = @($Approved.IntendedWrites)
                                ObservedPaths = @(); RecoveryLocations = @()
                            } | ConvertTo-Json -Depth 100
                        }
                        Set-InventoryFile $Root "$Relative/operation.json" $Receipt
                        [IO.File]::SetUnixFileMode((Join-Path $Root "$Relative/operation.json"), [IO.UnixFileMode]384)
                    }
                }
            }
        }
        $Before = Get-InventoryState $Root
        $Result = Invoke-WorkspaceFixture
        $Result.Ready | Should -BeFalse
        $Result.Fingerprint | Should -BeNullOrEmpty
        if ($Fault -in @('owner', 'lock', 'Prepared', 'Running', 'Attempting', 'Completed-inconsistent', 'torn', 'missing-receipt')) { $Result.Blockers.Code | Should -Contain 'OperationState' }
        Get-InventoryState $Root | Should -BeExactly $Before
    }
}
