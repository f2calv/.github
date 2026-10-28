#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Git-Process.ps1')
    $script:Python = if ($env:SKILL_LIBRARY_TEST_PYTHON) { $env:SKILL_LIBRARY_TEST_PYTHON } else { 'python3' }
    $script:ArchiveScript = Join-Path $PSScriptRoot '../Invoke-Archive.ps1'
    $script:WriterScript = Join-Path $PSScriptRoot '../Write-Archive.py'
    . (Join-Path $PSScriptRoot '../Invoke-InventoryPreview.ps1')
    . $script:ArchiveScript

    function Invoke-ArchiveFixtureGit {
        param([string]$Root, [string[]]$Arguments)
        $Prefix = [IO.Path]::GetFullPath($TestDrive) + [IO.Path]::DirectorySeparatorChar
        if (-not [IO.Path]::GetFullPath($Root).StartsWith($Prefix, [StringComparison]::Ordinal)) {
            throw 'Fixture Git mutations must remain inside TestDrive.'
        }
        $Result = Invoke-LibraryGit -Root $Root -Arguments $Arguments
        if ($Result.ExitCode -ne 0) { throw 'Synthetic Git operation failed.' }
        [Text.UTF8Encoding]::new($false, $true).GetString($Result.Bytes).TrimEnd("`n", "`r")
    }

    function Set-ArchiveFixtureFile {
        param([string]$Root, [string]$Path, [string]$Text = '', [byte[]]$Bytes)
        $FullPath = [IO.Path]::GetFullPath((Join-Path $Root $Path))
        if (-not $FullPath.StartsWith([IO.Path]::GetFullPath($TestDrive) + '/', [StringComparison]::Ordinal) -or
            -not $FullPath.StartsWith([IO.Path]::GetFullPath($Root) + '/', [StringComparison]::Ordinal)) {
            throw 'Fixture writes must remain inside their temporary repository.'
        }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($FullPath))
        if ($PSBoundParameters.ContainsKey('Bytes')) { [IO.File]::WriteAllBytes($FullPath, $Bytes) }
        else { [IO.File]::WriteAllText($FullPath, $Text) }
    }

    function Set-ArchiveFixtureSkill {
        param([string]$Root, [string]$Name, [hashtable]$Fields = @{})
        Set-ArchiveFixtureFile $Root ".github/skills/$Name/SKILL.md" "---`nname: $Name`ndescription: Synthetic fixture.`n---`n# Example`n"
        $Record = [ordered]@{ id = $Name; version = '1.0.0' }
        foreach ($Key in $Fields.Keys) { $Record[$Key] = $Fields[$Key] }
        Set-ArchiveFixtureFile $Root ".github/skills/$Name/skill.metadata.yaml" (ConvertTo-Json $Record -Depth 32)
    }

    function Save-ArchiveFixture {
        param([string]$Root)
        $EmptyHooks = Join-Path $Root '.git/empty-hooks'
        [void][IO.Directory]::CreateDirectory($EmptyHooks)
        [void](Invoke-ArchiveFixtureGit $Root @('add', '-A'))
        [void](Invoke-ArchiveFixtureGit $Root @('-c', "core.hooksPath=$EmptyHooks", '-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'Synthetic fixture'))
        Invoke-ArchiveFixtureGit $Root @('rev-parse', 'HEAD')
    }

    function Read-ArchiveFixture {
        param([string]$Path)
        $Stream = [IO.File]::OpenRead($Path)
        $Zip = [IO.Compression.ZipArchive]::new($Stream, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $Files = @{}
            foreach ($Entry in $Zip.Entries) {
                $InputStream = $Entry.Open()
                $Buffer = [IO.MemoryStream]::new()
                try { $InputStream.CopyTo($Buffer); $Files[$Entry.FullName] = $Buffer.ToArray() }
                finally { $InputStream.Dispose(); $Buffer.Dispose() }
            }
            [pscustomobject]@{
                Names = @($Zip.Entries.FullName)
                Manifest = ([Text.UTF8Encoding]::new($false, $true).GetString($Files['manifest.json']) | ConvertFrom-Json)
                Files = $Files
            }
        }
        finally { $Zip.Dispose(); $Stream.Dispose() }
    }

    function Invoke-ArchiveFixtureBuild {
        param([string]$Revision = 'HEAD', [string]$Destination = $script:Destination)
        Invoke-SkillArchive -RepoRoot $script:Root -SourceRevision $Revision -SkillName example -OutputDirectory $Destination -PythonPath $script:Python
    }

    function Get-ArchiveFixtureState {
        param([string]$Root)
        $Files = [Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
        foreach ($Item in Get-ChildItem -LiteralPath $Root -File -Recurse -Force) {
            if ($Item.FullName.StartsWith((Join-Path $Root '.git') + '/', [StringComparison]::Ordinal)) { continue }
            $Relative = [IO.Path]::GetRelativePath($Root, $Item.FullName)
            $Files[$Relative] = (Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256).Hash + ':' + [IO.File]::GetUnixFileMode($Item.FullName)
        }
        $GitFiles = @{}
        foreach ($Name in @('HEAD', 'index', 'config')) { $GitFiles[$Name] = (Get-FileHash -LiteralPath (Join-Path $Root ".git/$Name") -Algorithm SHA256).Hash }
        [ordered]@{
            Files = $Files; GitFiles = $GitFiles
            Refs = (Invoke-ArchiveFixtureGit $Root @('for-each-ref', '--format=%(refname) %(objectname)'))
        } | ConvertTo-Json -Depth 32 -Compress
    }

    function Test-ArchiveFixtureJsonEqual {
        param([object]$Left, [object]$Right)
        $LeftNode = [Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json -InputObject $Left -Depth 64 -Compress))
        $RightNode = [Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json -InputObject $Right -Depth 64 -Compress))
        [Text.Json.Nodes.JsonNode]::DeepEquals($LeftNode, $RightNode)
    }

    $script:FaultProbe = @'
import hashlib, io, json, os, pathlib, runpy, shutil, sys, tempfile
scope = runpy.run_path(sys.argv[1],run_name="archive_import")
globals_ = scope["main"].__globals__
fault = sys.argv[2]
messages, seen = [], []
with tempfile.TemporaryDirectory(prefix="archive-fault-test-") as temporary:
    parent = pathlib.Path(temporary)
    scratch = parent / "scratch"
    (scratch / "payload").mkdir(parents=True)
    content = b"synthetic committed bytes\r\n"
    (scratch / "payload" / "0").write_bytes(content)
    destination = parent / "output"
    request = {
        "SourceCommit":"1"*40,"Root":{"Id":"example","Version":"1.0.0","Folder":".github/skills/example"},
        "Builder":{"Contract":"skill-archive/1","ValidationRules":"invoked-tool-bundle",
            "Files":[{"Path":"scripts/example.py","Sha256":"0"*64}],
            "Runtimes":{"PowerShell":"7.6.9","Git":"2.56.0","Python":{"Implementation":"CPython","Version":"3.13.5"},"PyYAML":"6.0.3"}},
        "Components":[{"SourceCommit":"1"*40,"Reasons":[{"Kind":"root"}]}],
        "Payload":[{"SourcePath":".github/skills/example/SKILL.md","MemberPath":"payload/.github/skills/example/SKILL.md",
            "Mode":"100644","Size":len(content),"Sha256":hashlib.sha256(content).hexdigest(),
            "Owners":["example"],"Reasons":[],"StagedPath":str(scratch/"payload"/"0")}],
        "Destination":str(destination),"Boundaries":[],"Scratch":str(scratch),
    }
    original_open, original_sync = os.open, os.fsync
    original_hash = hashlib.sha256
    def fail(*arguments, **keywords):
        raise OSError("synthetic secret diagnostic must not escape")
    def checkpoint(name, output):
        if not seen:
            seen.append(output)
        if name == fault:
            raise scope["ArchiveError"]("Archive: Synthetic injected failure.")
        if name == "before-staged-read" and fault == "staged-change":
            (scratch / "payload" / "0").write_bytes(b"changed")
        if name == "marker-created" and fault == "create-failure":
            def open_probe(path, *arguments, **keywords):
                if path == "package.zip":
                    return fail()
                return original_open(path,*arguments,**keywords)
            os.open = open_probe
        if name == "created:package.zip":
            if fault == "write-failure":
                stream = output.handles[-1]
                original_write = stream.write
                def write_probe(data):
                    original_write(data[:max(1,len(data)//2)])
                    return fail()
                stream.write = write_probe
            elif fault == "close-failure":
                output.handles[-1].close = fail
            elif fault == "sync-failure":
                os.fsync = fail
        if name == "before-hash" and fault == "hash-failure":
            hashlib.sha256 = fail
        if name == "checksum-synced":
            if fault == "foreign-addition":
                (destination / "foreign.txt").write_bytes(b"caller-owned")
            elif fault == "replacement":
                (destination / "package.zip").unlink()
                (destination / "package.zip").write_bytes(b"replacement")
            elif fault == "changed-content":
                (destination / "package.zip").write_bytes(b"changed caller bytes")
            elif fault == "hardlink":
                os.link(destination/"package.zip",parent/"alias.zip")
    def emit(message):
        messages.append(message)
        if message["Status"] == "Prepared" and fault != "scratch-not-cleaned":
            shutil.rmtree(scratch)
    globals_["_checkpoint"] = checkpoint
    globals_["_emit"] = emit
    original_stdin = sys.stdin
    sys.stdin = io.StringIO(json.dumps(request)+"\nfinalize\n")
    try:
        result = scope["main"]()
    finally:
        sys.stdin = original_stdin
        os.open, os.fsync, hashlib.sha256 = original_open, original_sync, original_hash
        for output in seen:
            for stream in output.handles:
                io.FileIO.close(stream)
    assert result == 1, (fault,messages)
    assert messages[-1]["Status"] == "Failed" and not any(message["Status"] == "Completed" for message in messages)
    assert "ArchiveSha256" not in json.dumps(messages) and "synthetic secret" not in json.dumps(messages)
    if fault == "foreign-addition":
        assert (destination/"foreign.txt").read_bytes() == b"caller-owned"
    elif fault == "replacement":
        assert (destination/"package.zip").read_bytes() == b"replacement"
    elif fault == "changed-content":
        assert (destination/"package.zip").read_bytes() == b"changed caller bytes"
    elif fault == "hardlink":
        assert (destination/"package.zip").read_bytes() == (parent/"alias.zip").read_bytes()
    elif fault in ("handles-closed","before-final-acknowledgment","close-failure"):
        assert destination.exists() and messages[-1]["Category"] == "Cleanup"
    else:
        assert not destination.exists(), (fault,list(destination.iterdir()))
'@

    function New-ArchiveFixture {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($Root)
        $Template = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($Template)
        [void](Invoke-ArchiveFixtureGit $Root @('init', '-q', "--template=$Template"))
        Set-ArchiveFixtureFile $Root '.config/skill-library.yaml' "license: MIT`nnotices: [LICENSE]`n"
        Set-ArchiveFixtureFile $Root 'LICENSE' "Synthetic notice.`n"
        Set-ArchiveFixtureFile $Root '.github/skills/example/SKILL.md' "---`nname: example`ndescription: Synthetic fixture.`n---`n# Example`n"
        Set-ArchiveFixtureFile $Root '.github/skills/example/skill.metadata.yaml' "id: example`nversion: 1.0.0`n"
        [void](Invoke-ArchiveFixtureGit $Root @('add', '-A'))
        [void](Invoke-ArchiveFixtureGit $Root @('-c', "core.hooksPath=$Template", '-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Synthetic fixture'))
        return $Root
    }

    function Copy-ArchiveFixtureBundle {
        $Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../..') -Destination $Destination -Recurse
        return $Destination
    }
}

Describe 'Archive loading and fixtures' -Tag 'Unit' {
    It 'dot-sources without output, writes or exiting the host' {
        $Output = @(. $script:ArchiveScript)
        $Output.Count | Should -Be 0
        Get-Command Invoke-SkillArchive | Should -Not -BeNullOrEmpty
    }

    It 'imports the Python writer without running its entry point' {
        $Probe = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', 'import runpy,sys; runpy.run_path(sys.argv[1], run_name="archive_import")', $script:WriterScript)
        $Probe.ExitCode | Should -Be 0
        $Probe.Bytes.Length | Should -Be 0
        $Probe.Error | Should -BeExactly ''
    }

    It 'creates a committed temporary fixture and copies the complete trusted bundle' {
        $Root = New-ArchiveFixture
        (Invoke-ArchiveFixtureGit $Root @('rev-parse', 'HEAD')) | Should -Match '^[0-9a-f]{40,64}$'
        $Bundle = Copy-ArchiveFixtureBundle
        foreach ($Path in @('scripts/Invoke-Archive.ps1', 'scripts/Write-Archive.py', 'scripts/Invoke-InventoryPreview.ps1', 'scripts/Invoke-Validation.ps1', 'scripts/Git-Process.ps1', 'scripts/Read-Metadata.py', 'skill-metadata.schema.json', 'repository-defaults.schema.json', 'scripts/requirements.txt')) {
            Test-Path -LiteralPath (Join-Path $Bundle $Path) -PathType Leaf | Should -BeTrue
        }
    }
}

Describe 'Archive foundations' -Tag 'Unit' {
    It 'captures and hashes exactly the complete trusted bundle' {
        $Destination = Join-Path $TestDrive 'capture'
        $Files = Copy-ArchiveBundle -Destination $Destination
        $Files.Count | Should -Be 9
        foreach ($File in $Files) {
            $Actual = (Get-FileHash -LiteralPath (Join-Path $Destination $File.Path) -Algorithm SHA256).Hash.ToLowerInvariant()
            $File.Sha256 | Should -BeExactly $Actual
        }
    }

    It 'rejects zero, repeated or multiple roots without output' -ForEach @(
        @{ Names = @() }, @{ Names = @('example', 'example') }, @{ Names = @('example', 'other') }
    ) {
        { Invoke-SkillArchive -SkillName $Names -OutputDirectory (Join-Path $TestDrive 'invalid') } | Should -Throw 'Selection:*'
        Test-Path -LiteralPath (Join-Path $TestDrive 'invalid') | Should -BeFalse
    }

    It 'rejects optional selection even when empty' {
        { Invoke-SkillArchive -SkillName example -OptionalSelection @() } | Should -Throw '*parameter*OptionalSelection*'
    }

    It 'fails safely and removes scratch if capture cannot finish' {
        $Root = New-ArchiveFixture
        $script:CleanedScratch = $null
        Mock Copy-ArchiveBundle { throw 'Inspection: Synthetic capture failure.' }
        Mock Remove-ArchiveScratch {
            param($Path)
            $script:CleanedScratch = $Path
            [IO.Directory]::Delete($Path, $true)
        }
        { Invoke-SkillArchive -RepoRoot $Root -SkillName example -OutputDirectory (Join-Path $TestDrive 'capture-failure') -PythonPath $script:Python } | Should -Throw 'Inspection:*'
        $script:CleanedScratch | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:CleanedScratch | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $TestDrive 'capture-failure') | Should -BeFalse
    }

    It 'rolls back unchanged owned files but preserves foreign additions' {
        $Code = @'
import pathlib, runpy, sys, tempfile
scope = runpy.run_path(sys.argv[1], run_name="archive_import")
output_type = scope["_Output"]
with tempfile.TemporaryDirectory(prefix="archive-ownership-test-") as temporary:
    destination = pathlib.Path(temporary) / "owned"
    owned = output_type(str(destination), [])
    owned.reserve()
    with owned.create("probe.bin") as stream:
        stream.write(bytes([0,255,13,10]))
    owned.verify({".incomplete", "probe.bin"})
    assert owned.rollback() and not destination.exists()
    retained = output_type(str(destination), [])
    retained.reserve()
    (destination / "foreign.txt").write_bytes(b"caller-owned")
    assert not retained.rollback()
    assert (destination / "foreign.txt").read_bytes() == b"caller-owned"
'@
        $Probe = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $Code, $script:WriterScript)
        $Probe.ExitCode | Should -Be 0 -Because $Probe.Error
        $Probe.Bytes.Length | Should -Be 0
    }
}

Describe 'Required-only archives' -Tag 'Unit' {
    BeforeEach {
        $script:Root = New-ArchiveFixture
        $script:Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'stages exact inventory blobs before invoking the writer' {
        $Scratch = Join-Path $TestDrive 'adapter-stage'
        [void][IO.Directory]::CreateDirectory($Scratch)
        $Request = [pscustomobject]@{
            Root = $script:Root; Commit = (Invoke-ArchiveFixtureGit $script:Root @('rev-parse', 'HEAD'))
            Name = 'example'; Python = $script:Python; Rules = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
            Scratch = $Scratch; Output = $script:Destination; Builder = @{}; Boundaries = @($script:Root)
        }
        Mock Invoke-ArchiveWriter { throw 'Archive: Staged successfully.' }
        { Invoke-ArchiveCaptured -Request $Request } | Should -Throw 'Archive: Staged successfully.'
        @(Get-ChildItem -LiteralPath (Join-Path $Scratch 'payload')).Count | Should -Be 3
    }

    It 'returns one completed pair with exact minimal committed payload and evidence' {
        $Commit = Invoke-ArchiveFixtureGit $script:Root @('rev-parse', 'HEAD')
        $Results = @(Invoke-ArchiveFixtureBuild)
        $Results.Count | Should -Be 1
        $Result = $Results[0]
        $Result.SourceCommit | Should -BeExactly $Commit
        $Result.RootId | Should -BeExactly 'example'
        $Result.RootVersion | Should -BeExactly '1.0.0'
        $Result.ArchiveContract | Should -BeExactly 'skill-archive/1'
        @(Get-ChildItem -LiteralPath $script:Destination -Force).Name -join ',' | Should -BeExactly 'package.zip,package.zip.sha256'
        $Read = Read-ArchiveFixture $Result.ArchivePath
        $Read.Names -join ',' | Should -BeExactly 'manifest.json,payload/.github/skills/example/SKILL.md,payload/.github/skills/example/skill.metadata.yaml,payload/LICENSE'
        @($Read.Manifest.OptionalSelections).Count | Should -Be 0
        $Read.Manifest.GeneratedMembers.GetType().IsArray | Should -BeTrue
        $Read.Manifest.Payload.Count | Should -Be 3
        $Hash = (Get-FileHash -LiteralPath $Result.ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $Result.ArchiveSha256 | Should -BeExactly $Hash
        [IO.File]::ReadAllText($Result.ChecksumPath) | Should -BeExactly "$Hash  package.zip`n"
    }

    It 'includes a required diamond once, preserves notices and never follows optional-only edges' {
        Set-ArchiveFixtureSkill $script:Root 'leaf'
        foreach ($Name in @('left', 'right')) {
            Set-ArchiveFixtureSkill $script:Root $Name @{ required = @(@{ id = 'leaf'; version = '1.0.0' }) }
        }
        Set-ArchiveFixtureSkill $script:Root 'optional-leaf'
        Set-ArchiveFixtureSkill $script:Root 'optional' @{ required = @(@{ id = 'optional-leaf'; version = '1.0.0' }) }
        Set-ArchiveFixtureFile $script:Root 'NOTICES' "Synthetic additional notice.`n"
        Set-ArchiveFixtureFile $script:Root '.github/instructions/example.instructions.md' "Synthetic required guidance.`n"
        Set-ArchiveFixtureSkill $script:Root 'example' @{
            required = @(@{ id = 'left'; version = '1.0.0' }, @{ id = 'right'; version = '1.0.0' })
            optional = @(
                @{ id = 'optional'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic related choice.' },
                @{ id = 'leaf'; version = '1.0.0'; selectionKey = 'overlap'; reason = 'Already required independently.' }
            )
            notices = @('NOTICES')
            externalFiles = @(
                @{ path = '.github/instructions/example.instructions.md'; kind = 'instruction'; loadingPurpose = 'Synthetic required guidance.' }
            )
        }
        Set-ArchiveFixtureSkill $script:Root 'left' @{
            required = @(@{ id = 'leaf'; version = '1.0.0' })
            externalFiles = @(@{ path = 'NOTICES'; kind = 'notice'; loadingPurpose = 'Synthetic notice attribution.' })
        }
        [void](Save-ArchiveFixture $script:Root)
        $Result = Invoke-ArchiveFixtureBuild
        $Read = Read-ArchiveFixture $Result.ArchivePath
        $Read.Manifest.Components.Id -join ',' | Should -BeExactly 'example,leaf,left,right'
        $Read.Names -join ',' | Should -Not -Match '/optional(?:-leaf)?/'
        @($Read.Names | Select-Object -Unique).Count | Should -Be $Read.Names.Count
        $Read.Manifest.Payload.Count | Should -Be 11
        @($Read.Manifest.Payload | Where-Object SourcePath -EQ 'LICENSE').Owners.Count | Should -Be 4
        $Notice = $Read.Manifest.Payload | Where-Object SourcePath -EQ 'NOTICES'
        $Notice.Reasons.Kind -join ',' | Should -Match 'component-notice,external-notice'
        $Instruction = $Read.Manifest.Payload | Where-Object SourcePath -EQ '.github/instructions/example.instructions.md'
        $Instruction.Reasons[0].LoadingPurpose | Should -BeExactly 'Synthetic required guidance.'
        $Preview = Invoke-SkillInventoryPreview -RepoRoot $script:Root -SkillName example -OptionalSelection example/extra -PythonPath $script:Python
        $Preview.Components.Id | Should -Contain 'optional-leaf'
    }

    It 'packages committed binary, empty, Unicode content and CRLF bytes rather than working files' {
        $Binary = [byte[]]@(0, 255, 13, 10, 128)
        Set-ArchiveFixtureFile $script:Root '.github/skills/example/data.bin' -Bytes $Binary
        Set-ArchiveFixtureFile $script:Root '.github/skills/example/empty.txt' -Bytes ([byte[]]@())
        $UnicodeBytes = [Text.Encoding]::UTF8.GetBytes(([string][char]0x03BB) + "`r`n")
        Set-ArchiveFixtureFile $script:Root '.github/skills/example/unicode.txt' -Bytes $UnicodeBytes
        $Commit = Save-ArchiveFixture $script:Root
        Set-ArchiveFixtureFile $script:Root '.github/skills/example/data.bin' 'Dirty local content.'
        [IO.File]::Delete((Join-Path $script:Root '.github/skills/example/unicode.txt'))
        $Result = Invoke-ArchiveFixtureBuild -Revision $Commit
        $Read = Read-ArchiveFixture $Result.ArchivePath
        $Read.Files['payload/.github/skills/example/data.bin'] | Should -Be $Binary
        $Read.Files['payload/.github/skills/example/unicode.txt'] | Should -Be $UnicodeBytes
        $Read.Files['payload/.github/skills/example/empty.txt'].Length | Should -Be 0
    }

    It 'validates invalid unselected catalog records and leaves no output' {
        Set-ArchiveFixtureSkill $script:Root 'unselected' @{ version = 'not-a-version' }
        [void](Save-ArchiveFixture $script:Root)
        { Invoke-ArchiveFixtureBuild } | Should -Throw 'Validation:*'
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
    }

    It 'matches every manifest attribution and digest to the committed inventory and detects tampering' {
        $Preview = Invoke-SkillInventoryPreview -RepoRoot $script:Root -SkillName example -PythonPath $script:Python
        $Result = Invoke-ArchiveFixtureBuild
        $Read = Read-ArchiveFixture $Result.ArchivePath
        Test-ArchiveFixtureJsonEqual $Read.Manifest.Components $Preview.Components | Should -BeTrue
        $Read.Manifest.Payload.Count | Should -Be $Preview.Files.Count
        foreach ($File in $Preview.Files) {
            $Record = $Read.Manifest.Payload | Where-Object SourcePath -CEQ $File.Path
            $Record.Mode | Should -BeExactly $File.Mode
            $Record.MemberPath | Should -BeExactly "payload/$($File.Path)"
            Test-ArchiveFixtureJsonEqual $Record.Owners $File.Owners | Should -BeTrue
            Test-ArchiveFixtureJsonEqual $Record.Reasons $File.Reasons | Should -BeTrue
            $Bytes = $Read.Files[$Record.MemberPath]
            $Record.Size | Should -Be $Bytes.LongLength
            $Record.Sha256 | Should -BeExactly ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant())
        }
        @($Read.Manifest.PSObject.Properties.Name) | Should -Not -Contain 'ArchiveSha256'
        @($Read.Manifest.GeneratedMembers[0].PSObject.Properties.Name) | Should -Not -Contain 'Sha256'
        $Changed = [IO.File]::ReadAllBytes($Result.ArchivePath)
        $Changed[0] = $Changed[0] -bxor 1
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Changed)).ToLowerInvariant() | Should -Not -BeExactly $Result.ArchiveSha256
    }

    It 'rejects ignored mandatory files without output' {
        Set-ArchiveFixtureFile $script:Root '.gitignore' "LICENSE`n"
        [void](Save-ArchiveFixture $script:Root)
        { Invoke-ArchiveFixtureBuild } | Should -Throw 'Eligibility:*'
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
    }

    It 'provides one JSON CLI result and uses its own repository default independent of caller location' {
        $Tool = Join-Path $script:Root '.github/skills/skill-library'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../..') -Destination $Tool -Recurse
        $ScriptPath = Join-Path $Tool 'scripts/Invoke-Archive.ps1'
        $PreviousLocation = Get-Location
        try {
            Set-Location -LiteralPath $TestDrive
            $Cli = Invoke-LibraryProcess -Executable (Get-Process -Id $PID).Path -Arguments @('-NoProfile', '-File', $ScriptPath, '-SkillName', 'example', '-OutputDirectory', $script:Destination, '-PythonPath', $script:Python)
        }
        finally { Set-Location -LiteralPath $PreviousLocation.Path }
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Cli.Error | Should -BeExactly ''
        $Json = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Json.RootId | Should -BeExactly 'example'
        $Json.OutputDirectory | Should -BeExactly $script:Destination
    }

    It 'fails CLI missing arguments noninteractively without stdout or source content' {
        $Cli = Invoke-LibraryProcess -Executable (Get-Process -Id $PID).Path -Arguments @('-NoProfile', '-NonInteractive', '-File', $script:ArchiveScript)
        $Cli.ExitCode | Should -Be 1
        $Cli.Bytes.Length | Should -Be 0
        $Cli.Error | Should -Match '^Selection:'
    }
}

Describe 'Deterministic archive bytes' -Tag 'Unit' {
    BeforeEach {
        $script:Root = New-ArchiveFixture
        $script:Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'has independently normalized local and central headers, exact evidence and hashes' {
        Set-ArchiveFixtureFile $script:Root '.github/skills/example/run.sh' "#!/bin/sh`nprintf inert`n"
        [IO.File]::SetUnixFileMode((Join-Path $script:Root '.github/skills/example/run.sh'), [IO.UnixFileMode]493)
        [void](Save-ArchiveFixture $script:Root)
        $Result = Invoke-ArchiveFixtureBuild
        $Code = @'
import binascii, hashlib, json, pathlib, struct, sys, zipfile
path = pathlib.Path(sys.argv[1])
raw = path.read_bytes()
end = struct.unpack_from("<4s4H2IH", raw, len(raw)-22)
assert end[0] == b"PK\x05\x06" and end[1:3] == (0,0) and end[3] == end[4] and end[7] == 0
assert end[5] + end[6] == len(raw)-22
with zipfile.ZipFile(path) as archive:
    names = archive.namelist()
    assert names == ["manifest.json"] + sorted(names[1:], key=lambda name: name.encode("utf-8"))
    manifest_raw = archive.read("manifest.json")
    model = json.loads(manifest_raw)
    assert manifest_raw.startswith(b'{"Builder":') and manifest_raw.endswith(b"\n") and not manifest_raw.endswith(b"\n\n")
    assert manifest_raw == (json.dumps(model,sort_keys=True,ensure_ascii=False,allow_nan=False,separators=(",",":"))+"\n").encode("utf-8")
    assert set(model) == {"SchemaVersion","SourceCommit","Root","OptionalSelections","Builder","Components","Payload","GeneratedMembers","Limitations"}
    assert model["SchemaVersion"] == 1 and model["OptionalSelections"] == []
    assert model["GeneratedMembers"] == [{"Path":"manifest.json","Role":"build-evidence","Mode":"100644"}]
    assert set(model["Builder"]["Runtimes"]) == {"PowerShell","Git","Python","PyYAML"}
    assert len(model["Builder"]["Files"]) == 9
    records = {record["MemberPath"]:record for record in model["Payload"]}
    cursor = end[6]
    local_cursor = 0
    for member in archive.infolist():
        central = struct.unpack_from("<4s6H3I5H2I",raw,cursor)
        local = struct.unpack_from("<4s5H3I2H",raw,local_cursor)
        expected_flag = 0 if member.filename.isascii() else 0x800
        mode = "100644" if member.filename == "manifest.json" else records[member.filename]["Mode"]
        data = archive.read(member.filename)
        name = member.filename.encode("utf-8")
        assert central[:7] == (b"PK\x01\x02",0x0314,20,expected_flag,0,0,0x21)
        assert local[:6] == (b"PK\x03\x04",20,expected_flag,0,0,0x21)
        assert central[7:10] == local[6:9] == (binascii.crc32(data),len(data),len(data))
        assert central[10:15] == (len(name),0,0,0,0)
        assert central[15] == int(mode,8)<<16 and central[16] == local_cursor
        assert local[9:11] == (len(name),0)
        assert raw[cursor+46:cursor+46+len(name)] == name
        assert raw[local_cursor+30:local_cursor+30+len(name)] == name
        if member.filename != "manifest.json":
            record = records[member.filename]
            assert record["Size"] == len(data) and record["Sha256"] == hashlib.sha256(data).hexdigest()
            assert isinstance(record["Owners"],list) and isinstance(record["Reasons"],list)
        cursor += 46+len(name)
        local_cursor += 30+len(name)+len(data)
    assert cursor == len(raw)-22 and local_cursor == end[6]
    assert records["payload/.github/skills/example/run.sh"]["Mode"] == "100755"
assert path.with_name("package.zip.sha256").read_bytes() == (hashlib.sha256(raw).hexdigest()+"  package.zip\n").encode("ascii")
'@
        $Inspect = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $Code, $Result.ArchivePath)
        $Inspect.ExitCode | Should -Be 0 -Because $Inspect.Error
        $Inspect.Bytes.Length | Should -Be 0
    }

    It 'rebuilds identical bytes under changed caller, locale, timezone and umask while excluding dirty source' {
        $Commit = Invoke-ArchiveFixtureGit $script:Root @('rev-parse', 'HEAD')
        $First = Invoke-ArchiveFixtureBuild -Revision $Commit
        Set-ArchiveFixtureFile $script:Root 'LICENSE' "Dirty staged notice.`n"
        [void](Invoke-ArchiveFixtureGit $script:Root @('add', 'LICENSE'))
        [IO.File]::Delete((Join-Path $script:Root '.github/skills/example/SKILL.md'))
        Set-ArchiveFixtureFile $script:Root 'untracked.txt' 'Not payload.'
        $SecondDestination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Code = @'
import os, subprocess, sys
os.umask(0o077)
environment = dict(os.environ, LC_ALL="C", TZ="Pacific/Honolulu")
result = subprocess.run(sys.argv[1:],cwd="/",env=environment,capture_output=True,check=False)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
'@
        $Cli = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $Code, (Get-Process -Id $PID).Path, '-NoProfile', '-File', $script:ArchiveScript, '-RepoRoot', $script:Root, '-SourceRevision', $Commit, '-SkillName', 'example', '-OutputDirectory', $SecondDestination, '-PythonPath', $script:Python)
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Second = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        [IO.File]::ReadAllBytes($Second.ArchivePath) | Should -Be ([IO.File]::ReadAllBytes($First.ArchivePath))
        $Second.ArchiveSha256 | Should -BeExactly $First.ArchiveSha256
        [IO.File]::ReadAllText((Join-Path $script:Root 'LICENSE')) | Should -BeExactly "Dirty staged notice.`n"
        [IO.File]::Exists((Join-Path $script:Root '.github/skills/example/SKILL.md')) | Should -BeFalse
    }

    It 'changes the artifact when an eligible committed blob changes' {
        $First = Invoke-ArchiveFixtureBuild
        $FirstRead = Read-ArchiveFixture $First.ArchivePath
        Set-ArchiveFixtureFile $script:Root 'LICENSE' "Changed committed notice.`n"
        [void](Save-ArchiveFixture $script:Root)
        $Second = Invoke-ArchiveFixtureBuild -Destination (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $SecondRead = Read-ArchiveFixture $Second.ArchivePath
        $FirstRead.Files['payload/LICENSE'] | Should -Be ([Text.Encoding]::UTF8.GetBytes("Synthetic notice.`n"))
        $SecondRead.Files['payload/LICENSE'] | Should -Be ([Text.Encoding]::UTF8.GetBytes("Changed committed notice.`n"))
        ($FirstRead.Manifest.Payload | Where-Object SourcePath -CEQ 'LICENSE').Sha256 |
            Should -Not -BeExactly ($SecondRead.Manifest.Payload | Where-Object SourcePath -CEQ 'LICENSE').Sha256
        $Second.SourceCommit | Should -Not -BeExactly $First.SourceCommit
        $Second.ArchiveSha256 | Should -Not -BeExactly $First.ArchiveSha256
    }

    It 'rebuilds the older frozen commit after HEAD advances without using newer committed bytes' {
        $Commit = Invoke-ArchiveFixtureGit $script:Root @('rev-parse', 'HEAD')
        $First = Invoke-ArchiveFixtureBuild -Revision $Commit
        Set-ArchiveFixtureFile $script:Root 'LICENSE' "Newer HEAD notice.`n"
        $NewCommit = Save-ArchiveFixture $script:Root
        $NewCommit | Should -Not -BeExactly $Commit
        $Before = Get-ArchiveFixtureState $script:Root
        $Second = Invoke-ArchiveFixtureBuild -Revision $Commit -Destination (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $Second.SourceCommit | Should -BeExactly $Commit
        $Second.ArchiveSha256 | Should -BeExactly $First.ArchiveSha256
        [IO.File]::ReadAllBytes($Second.ArchivePath) | Should -Be ([IO.File]::ReadAllBytes($First.ArchivePath))
        $Read = Read-ArchiveFixture $Second.ArchivePath
        $Read.Files['payload/LICENSE'] | Should -Be ([Text.Encoding]::UTF8.GetBytes("Synthetic notice.`n"))
        [IO.File]::ReadAllText((Join-Path $script:Root 'LICENSE')) | Should -BeExactly "Newer HEAD notice.`n"
        (Get-ArchiveFixtureState $script:Root) | Should -BeExactly $Before
    }

    It 'rejects noncanonical values and classic ZIP limits before output reservation' {
        $Code = @'
import runpy, sys
scope = runpy.run_path(sys.argv[1],run_name="archive_import")
canonical, size = scope["_canonical"], scope["_predicted_size"]
for invalid in [1.5,float("nan"),float("inf"),{1:"key"},"\ud800"]:
    try:
        canonical(invalid)
    except (ValueError,UnicodeError,scope["ArchiveError"]):
        pass
    else:
        raise AssertionError("Invalid canonical JSON accepted")
assert canonical({"z":[],"a":[1]}) == b'{"a":[1],"z":[]}\n'
assert size(b"{}",[]) == 126
for records in [[{"MemberPath":"x","Size":1<<30}], [{"MemberPath":"x"*65490,"Size":0}], [{"MemberPath":"x","Size":0}]*65534]:
    try:
        size(b"{}",records)
    except scope["ArchiveError"]:
        pass
    else:
        raise AssertionError("ZIP limit accepted")
boundary = {"MemberPath":"x","Size":(1<<30)-204}
assert size(b"{}",[boundary]) == 1<<30
boundary["Size"] += 1
try:
    size(b"{}",[boundary])
except scope["ArchiveError"]:
    pass
else:
    raise AssertionError("Oversize ZIP accepted")
'@
        $Probe = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $Code, $script:WriterScript)
        $Probe.ExitCode | Should -Be 0 -Because $Probe.Error
    }

    It 'represents changed trusted builder bytes separately from the unchanged source commit' {
        $First = Invoke-ArchiveFixtureBuild
        $Bundle = Copy-ArchiveFixtureBundle
        [IO.File]::AppendAllText((Join-Path $Bundle 'scripts/Write-Archive.py'), "`n")
        $OtherDestination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Cli = Invoke-LibraryProcess -Executable (Get-Process -Id $PID).Path -Arguments @('-NoProfile', '-File', (Join-Path $Bundle 'scripts/Invoke-Archive.ps1'), '-RepoRoot', $script:Root, '-SkillName', 'example', '-OutputDirectory', $OtherDestination, '-PythonPath', $script:Python)
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Second = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Second.SourceCommit | Should -BeExactly $First.SourceCommit
        $Second.ArchiveSha256 | Should -Not -BeExactly $First.ArchiveSha256
        $FirstRead = Read-ArchiveFixture $First.ArchivePath
        $SecondRead = Read-ArchiveFixture $Second.ArchivePath
        ($FirstRead.Manifest.Builder.Files | Where-Object Path -EQ 'scripts/Write-Archive.py').Sha256 | Should -Not -BeExactly ($SecondRead.Manifest.Builder.Files | Where-Object Path -EQ 'scripts/Write-Archive.py').Sha256
        $Evidence = [Text.Encoding]::UTF8.GetString($SecondRead.Files['manifest.json'])
        foreach ($Path in @($script:Root, $Bundle, $OtherDestination, $script:Python)) { $Evidence.Contains($Path) | Should -BeFalse }
    }

    It 'uses the standard UTF-8 name flag without private encoders' {
        $Code = @'
import io, runpy, struct, sys, zipfile
scope = runpy.run_path(sys.argv[1],run_name="archive_import")
buffer = io.BytesIO()
with zipfile.ZipFile(buffer,"w",allowZip64=False) as archive:
    archive.writestr(scope["_zip_info"]("payload/"+chr(0x3bb)+".txt","100644"),b"content")
raw = buffer.getvalue()
assert struct.unpack_from("<H",raw,6)[0] == 0x800
assert chr(0x3bb).encode("utf-8") in raw
'@
        $Probe = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $Code, $script:WriterScript)
        $Probe.ExitCode | Should -Be 0 -Because $Probe.Error
    }
}

Describe 'Archive refusal and fault safety' -Tag 'Unit' {
    BeforeEach {
        $script:Root = New-ArchiveFixture
        $script:Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'preserves source files, index, HEAD, refs and local configuration on success and source refusal' {
        $Before = Get-ArchiveFixtureState $script:Root
        $null = Invoke-ArchiveFixtureBuild
        (Get-ArchiveFixtureState $script:Root) | Should -BeExactly $Before
        { Invoke-ArchiveFixtureBuild -Revision 'missing-local-commit' -Destination (Join-Path $TestDrive 'missing-source') } | Should -Throw 'Source:*'
        (Get-ArchiveFixtureState $script:Root) | Should -BeExactly $Before
    }

    It 'refuses existing entries and unsafe destinations without changing source' -ForEach @(
        @{ Kind = 'empty-directory' }, @{ Kind = 'nonempty-directory' }, @{ Kind = 'file' },
        @{ Kind = 'dangling-link' }, @{ Kind = 'linked-parent' }, @{ Kind = 'missing-parent' },
        @{ Kind = 'source' }, @{ Kind = 'git' }, @{ Kind = 'relative' }, @{ Kind = 'ambiguous' }
    ) {
        switch ($Kind) {
            'empty-directory' { [void][IO.Directory]::CreateDirectory($script:Destination) }
            'nonempty-directory' { [void][IO.Directory]::CreateDirectory($script:Destination); [IO.File]::WriteAllText((Join-Path $script:Destination 'foreign.txt'), 'caller-owned') }
            'file' { [IO.File]::WriteAllText($script:Destination, 'caller-owned') }
            'dangling-link' { [void][IO.File]::CreateSymbolicLink($script:Destination, (Join-Path $TestDrive 'missing-target')) }
            'linked-parent' { [void][IO.Directory]::CreateSymbolicLink($script:Destination, $TestDrive); $script:Destination += '/new' }
            'missing-parent' { $script:Destination += '/new' }
            'source' { $script:Destination = Join-Path $script:Root 'new-output' }
            'git' { $script:Destination = Join-Path $script:Root '.git/new-output' }
            'relative' { $script:Destination = 'relative-output' }
            'ambiguous' { $script:Destination = "$TestDrive/../ambiguous-output" }
        }
        $Before = Get-ArchiveFixtureState $script:Root
        { Invoke-ArchiveFixtureBuild } | Should -Throw 'Output:*'
        (Get-ArchiveFixtureState $script:Root) | Should -BeExactly $Before
        if ($Kind -eq 'nonempty-directory') { [IO.File]::ReadAllText((Join-Path $script:Destination 'foreign.txt')) | Should -BeExactly 'caller-owned' }
        if ($Kind -eq 'file') { [IO.File]::ReadAllText($script:Destination) | Should -BeExactly 'caller-owned' }
    }

    It 'permits a prefix-lookalike sibling outside the repository' {
        $Result = Invoke-ArchiveFixtureBuild -Destination ($script:Root + '-output')
        Test-Path -LiteralPath $Result.ArchivePath | Should -BeTrue
    }

    It 'rejects a missing installed interpreter without provisioning or output' {
        { Invoke-SkillArchive -RepoRoot $script:Root -SkillName example -OutputDirectory $script:Destination -PythonPath '/nonexistent/skill-archive-python' } | Should -Throw 'Prerequisite:*'
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
    }

    It 'fails on a missing committed blob without fetching, partial output or caller-state changes' {
        $Bundle = Copy-ArchiveFixtureBundle
        $Guard = @'
$OriginalArchiveGit = (Get-Command Invoke-LibraryGit).ScriptBlock
Set-Item -Path Function:Invoke-LibraryGit -Value {
    param([string]$Root, [string[]]$Arguments, [byte[]]$InputBytes, [System.Collections.IDictionary]$Environment = @{})
    foreach ($Forbidden in @('clone', 'fetch', 'pull', 'push', 'commit', 'tag', 'checkout', 'switch', 'reset', 'update-ref')) {
        if ($Arguments -contains $Forbidden) { throw 'Inspection: Synthetic remote/mutating Git tripwire.' }
    }
    & $OriginalArchiveGit @PSBoundParameters
}.GetNewClosure()
'@
        $Helper = Join-Path $Bundle 'scripts/Git-Process.ps1'
        [IO.File]::AppendAllText($Helper, "`n$Guard`n")
        & {
            param($Path, $Root)
            . $Path
            { Invoke-LibraryGit -Root $Root -Arguments @('fetch') } | Should -Throw 'Inspection: Synthetic*'
        } $Helper $script:Root
        $Blob = Invoke-ArchiveFixtureGit $script:Root @('rev-parse', 'HEAD:LICENSE')
        $ObjectPath = Join-Path $script:Root ('.git/objects/' + $Blob.Substring(0, 2) + '/' + $Blob.Substring(2))
        Test-Path -LiteralPath $ObjectPath -PathType Leaf | Should -BeTrue
        [IO.File]::Delete($ObjectPath)
        $Before = Get-ArchiveFixtureState $script:Root
        $Results = [Collections.Generic.List[object]]::new()
        $Failure = $null
        try {
            & {
                param($Tool, $Root, $Destination, $Python)
                . $Tool
                Invoke-SkillArchive -RepoRoot $Root -SkillName example -OutputDirectory $Destination -PythonPath $Python
            } (Join-Path $Bundle 'scripts/Invoke-Archive.ps1') $script:Root $script:Destination $script:Python |
                ForEach-Object { $Results.Add($_) }
        }
        catch { $Failure = $_.Exception.Message }
        $Failure | Should -Match '^Inspection:'
        $Failure | Should -Not -Match 'tripwire|ArchiveSha256|[0-9a-f]{64}'
        $Results.Count | Should -Be 0
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
        Test-Path -LiteralPath $ObjectPath | Should -BeFalse
        (Get-ArchiveFixtureState $script:Root) | Should -BeExactly $Before
    }

    It 'rejects committed symbolic-link payloads without output' {
        [void][IO.File]::CreateSymbolicLink((Join-Path $script:Root '.github/skills/example/linked.txt'), 'SKILL.md')
        [void](Save-ArchiveFixture $script:Root)
        { Invoke-ArchiveFixtureBuild } | Should -Throw 'Inspection:*'
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
    }

    It 'suppresses success when PowerShell scratch cleanup fails' {
        $script:RetainedScratch = $null
        Mock Remove-ArchiveScratch {
            param($Path)
            $script:RetainedScratch = $Path
            throw 'Synthetic cleanup failure.'
        }
        try {
            { Invoke-ArchiveFixtureBuild } | Should -Throw 'Cleanup:*'
            Test-Path -LiteralPath $script:Destination | Should -BeFalse
            Test-Path -LiteralPath $script:RetainedScratch -PathType Container | Should -BeTrue
        }
        finally {
            if ($script:RetainedScratch -and [IO.Directory]::Exists($script:RetainedScratch)) { [IO.Directory]::Delete($script:RetainedScratch, $true) }
        }
    }

    It 'identifies retained inventory scratch when inspection cleanup fails without partial success' {
        $Bundle = Copy-ArchiveFixtureBundle
        $Recorder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.txt')
        $Override = @'
function Remove-InventoryScratch {
    param([string]$Path)
    [IO.File]::WriteAllText('__RECORDER__', $Path)
    throw 'Synthetic secret cleanup diagnostic must not escape.'
}
'@.Replace('__RECORDER__', $Recorder.Replace("'", "''"))
        [IO.File]::AppendAllText((Join-Path $Bundle 'scripts/Invoke-InventoryPreview.ps1'), "`n$Override`n")
        $Before = Get-ArchiveFixtureState $script:Root
        $Results = [Collections.Generic.List[object]]::new()
        $Failure = $null
        try {
            try {
                & {
                    param($Tool, $Root, $Destination, $Python)
                    . $Tool
                    Invoke-SkillArchive -RepoRoot $Root -SkillName example -OutputDirectory $Destination -PythonPath $Python
                } (Join-Path $Bundle 'scripts/Invoke-Archive.ps1') $script:Root $script:Destination $script:Python |
                    ForEach-Object { $Results.Add($_) }
            }
            catch { $Failure = $_.Exception.Message }
            $Failure | Should -Match '^Cleanup:'
            $Failure | Should -Not -Match 'Synthetic secret|ArchiveSha256|[0-9a-f]{64}'
            Test-Path -LiteralPath $Recorder -PathType Leaf | Should -BeTrue
            $Retained = [IO.File]::ReadAllText($Recorder)
            $Failure.Contains($Retained) | Should -BeTrue
            Test-Path -LiteralPath $Retained -PathType Container | Should -BeTrue
            $Results.Count | Should -Be 0
            Test-Path -LiteralPath $script:Destination | Should -BeFalse
            (Get-ArchiveFixtureState $script:Root) | Should -BeExactly $Before
        }
        finally {
            if ([IO.File]::Exists($Recorder)) {
                $Retained = [IO.File]::ReadAllText($Recorder)
                if ([IO.Directory]::Exists($Retained)) { [IO.Directory]::Delete($Retained, $true) }
            }
        }
    }

    It 'refuses temporary storage inside source and preserves environment and caller state' {
        $Parent = Join-Path $script:Root 'temporary'
        [void][IO.Directory]::CreateDirectory($Parent)
        $Previous = [Environment]::GetEnvironmentVariable('TMPDIR')
        $Before = Get-ArchiveFixtureState $script:Root
        try {
            $env:TMPDIR = $Parent
            { Invoke-ArchiveFixtureBuild } | Should -Throw 'Output:*'
        }
        finally { [Environment]::SetEnvironmentVariable('TMPDIR', $Previous) }
        (Get-ArchiveFixtureState $script:Root) | Should -BeExactly $Before
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
    }

    It 'suppresses success and preserves ambiguous state at <Fault>' -ForEach (@(
        'reserved', 'marker-created', 'created:package.zip', 'before-staged-read', 'member-written',
        'zip-closed', 'zip-synced', 'before-hash', 'created:package.zip.sha256', 'checksum-synced',
        'scratch-acknowledged', 'marker-removed', 'directory-synced', 'handles-closed',
        'before-final-acknowledgment', 'staged-change', 'create-failure', 'write-failure',
        'close-failure', 'sync-failure', 'hash-failure', 'foreign-addition', 'replacement',
        'changed-content', 'hardlink', 'scratch-not-cleaned'
    ) | ForEach-Object { @{ Fault = $_ } }) {
        $Probe = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $script:FaultProbe, $script:WriterScript, $Fault)
        $Probe.ExitCode | Should -Be 0 -Because $Probe.Error
        $Probe.Bytes.Length | Should -Be 0
        $Probe.Error | Should -BeExactly ''
    }

    It 'allows exactly one competing reservation and refuses process-death remnants' {
        $Code = @'
import multiprocessing, pathlib, runpy, sys, tempfile
scope = runpy.run_path(sys.argv[1],run_name="archive_import")
context = multiprocessing.get_context("fork")
with tempfile.TemporaryDirectory(prefix="archive-race-test-") as temporary:
    destination = str(pathlib.Path(temporary)/"output")
    barrier, release, queue = context.Barrier(2), context.Event(), context.Queue()
    def contender():
        output = scope["_Output"](destination,[])
        barrier.wait(timeout=15)
        try:
            output.reserve()
        except FileExistsError:
            assert output.rollback()
            queue.put("loser")
        else:
            queue.put("winner")
            assert release.wait(timeout=15)
            assert output.rollback()
    children = [context.Process(target=contender) for _ in range(2)]
    for child in children:
        child.start()
    try:
        assert sorted(queue.get(timeout=15) for _ in children) == ["loser","winner"]
        assert (pathlib.Path(destination)/".incomplete").read_bytes() == b"skill-archive/1 incomplete\n"
    finally:
        release.set()
        for child in children:
            child.join(timeout=15)
            if child.is_alive():
                child.kill()
                child.join()
            assert child.exitcode == 0
    ready = context.Event()
    def interrupted():
        output = scope["_Output"](destination,[])
        output.reserve()
        ready.set()
        context.Event().wait()
    child = context.Process(target=interrupted)
    child.start()
    assert ready.wait(timeout=15)
    child.kill()
    child.join(timeout=15)
    directory = pathlib.Path(destination)
    for finalized in (False,True):
        if finalized:
            (directory/".incomplete").unlink()
            (directory/"package.zip").write_bytes(b"unacknowledged artifact")
            (directory/"package.zip.sha256").write_bytes(b"unacknowledged checksum")
        before = {item.name:item.read_bytes() for item in directory.iterdir()}
        retry = scope["_Output"](destination,[])
        try:
            retry.reserve()
        except FileExistsError:
            assert retry.rollback()
        else:
            raise AssertionError("Crash remnant adopted")
        assert before == {item.name:item.read_bytes() for item in directory.iterdir()}
'@
        $Probe = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $Code, $script:WriterScript)
        $Probe.ExitCode | Should -Be 0 -Because $Probe.Error
        $Probe.Bytes.Length | Should -Be 0
    }

    It 'rejects unsupported operating systems and Python implementations before reserving output' {
        $Code = @'
import pathlib, platform, runpy, sys, tempfile
scope = runpy.run_path(sys.argv[1],run_name="archive_import")
original_platform, original_implementation = sys.platform, platform.python_implementation
with tempfile.TemporaryDirectory(prefix="archive-platform-test-") as temporary:
    destination = str(pathlib.Path(temporary)/"output")
    try:
        for operating_system, implementation in [("win32","CPython"),("linux","PyPy")]:
            sys.platform = operating_system
            platform.python_implementation = lambda: implementation
            try:
                scope["_Output"](destination,[])
            except scope["ArchiveError"] as error:
                assert str(error).startswith("Prerequisite:")
            else:
                raise AssertionError("Unsupported runtime accepted")
            assert not pathlib.Path(destination).exists()
    finally:
        sys.platform, platform.python_implementation = original_platform, original_implementation
'@
        $Probe = Invoke-LibraryProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $Code, $script:WriterScript)
        $Probe.ExitCode | Should -Be 0 -Because $Probe.Error
    }

    It 'categorizes absent and malformed protocol messages without leaking writer stderr' {
        foreach ($Text in @('', "not-json`n", "{}`n")) {
            $Process = [pscustomobject]@{ StandardOutput = [IO.StringReader]::new($Text) }
            { Read-ArchiveWriterMessage -Process $Process -Destination $script:Destination } | Should -Throw 'Archive:*'
            $Process.StandardOutput.Dispose()
        }
        $Process = [pscustomobject]@{ StandardOutput = [IO.StringReader]::new('') }
        { Read-ArchiveWriterMessage -Process $Process -Destination $script:Destination -Category Cleanup } | Should -Throw 'Cleanup:*'
        $Process.StandardOutput.Dispose()
    }

    It 'detects prohibited process and network attempts and never executes historical payload code' {
        $Bundle = Copy-ArchiveFixtureBundle
        $Helper = Join-Path $Bundle 'scripts/Git-Process.ps1'
        $Guard = @'
$OriginalProcess = (Get-Command Invoke-LibraryProcess).ScriptBlock
$AllowedGit = (Get-Command git -CommandType Application -TotalCount 1).Source
$AllowedPython = $env:SKILL_LIBRARY_TEST_PYTHON
Set-Item -Path Function:Invoke-LibraryProcess -Value {
    param([string]$Executable, [string[]]$Arguments, [byte[]]$InputBytes, [System.Collections.IDictionary]$Environment = @{})
    if ($Executable -ceq $AllowedGit) {
        foreach ($Forbidden in @('clone','fetch','pull','push','commit','tag','checkout','switch','reset','update-ref')) {
            if ($Arguments -contains $Forbidden) { throw 'Tripwire: Mutating or remote Git command.' }
        }
    }
    elseif ($Executable -ceq $AllowedPython) {
        if ($Arguments.Count -lt 3 -or $Arguments[0] -cne '-I' -or $Arguments[1] -cne '-B') { throw 'Tripwire: Python provisioning or unisolated execution.' }
        if ($Arguments[2] -eq '-c') {
            if (-not ($Arguments[3].StartsWith('import sys, yaml; sys.exit(') -or $Arguments[3].StartsWith('import json,platform,sys,yaml; assert '))) { throw 'Tripwire: Unexpected Python operation.' }
        }
        elseif ([IO.Path]::GetFileName($Arguments[2]) -cne 'Read-Metadata.py') { throw 'Tripwire: Unexpected Python program.' }
    }
    else { throw 'Tripwire: Download, provisioning, install, version preparation or publication process.' }
    & $OriginalProcess @PSBoundParameters
}.GetNewClosure()
'@
        [IO.File]::AppendAllText($Helper, "`n$Guard`n")
        $Sentinel = Join-Path $TestDrive 'historical-code-was-executed'
        Set-ArchiveFixtureFile $script:Root '.github/skills/example/scripts/Read-Metadata.py' "from pathlib import Path`nPath('$Sentinel').write_text('must not execute')`nraise RuntimeError('historical code executed')`n"
        Set-ArchiveFixtureFile $script:Root '.github/skills/skill-library/scripts/Invoke-Archive.ps1' "throw 'Historical tool must remain inert.'`n"
        [void](Save-ArchiveFixture $script:Root)
        $Before = Get-ArchiveFixtureState $script:Root
        . $Helper
        foreach ($Tool in @('curl', 'npm', 'pip', 'gh', 'pwsh')) {
            { Invoke-LibraryProcess -Executable $Tool -Arguments @('blocked-synthetic-attempt') } | Should -Throw 'Tripwire:*'
        }
        { Invoke-LibraryProcess -Executable (Get-Command git -CommandType Application -TotalCount 1).Source -Arguments @('push') } | Should -Throw 'Tripwire:*'
        { Invoke-LibraryProcess -Executable $script:Python -Arguments @('-m', 'pip', 'install', 'example') } | Should -Throw 'Tripwire:*'
        $Writer = Join-Path $Bundle 'scripts/Write-Archive.py'
        $Audit = @'
def _archive_test_audit(event, arguments):
    if event.startswith("socket.") or event in ("subprocess.Popen","os.system","os.exec","os.posix_spawn"):
        raise RuntimeError("Tripwire: prohibited network or subprocess attempt")
sys.addaudithook(_archive_test_audit)

'@
        [IO.File]::WriteAllText($Writer, [IO.File]::ReadAllText($Writer).Replace('if __name__ == "__main__":', $Audit + 'if __name__ == "__main__":'))
        $AuditProbe = @'
import runpy, socket, subprocess, sys
runpy.run_path(sys.argv[1],run_name="archive_import")
for operation in [lambda: socket.socket(),lambda: subprocess.run(["nonexistent-tripwire-command"],check=False)]:
    try:
        operation()
    except RuntimeError as error:
        assert str(error).startswith("Tripwire:")
    else:
        raise AssertionError("Tripwire did not block synthetic attempt")
'@
        $Probe = & $OriginalProcess -Executable $script:Python -Arguments @('-I', '-B', '-c', $AuditProbe, $Writer)
        $Probe.ExitCode | Should -Be 0 -Because $Probe.Error
        . (Join-Path $Bundle 'scripts/Invoke-Archive.ps1')
        $Result = Invoke-ArchiveFixtureBuild
        Test-Path -LiteralPath $Result.ArchivePath | Should -BeTrue
        Test-Path -LiteralPath $Sentinel | Should -BeFalse
        (Get-ArchiveFixtureState $script:Root) | Should -BeExactly $Before
    }
}
