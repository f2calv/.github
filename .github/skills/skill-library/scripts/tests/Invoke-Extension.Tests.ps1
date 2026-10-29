#!/usr/bin/env pwsh
#Requires -Version 7.4

BeforeAll {
    $script:Adapter = Join-Path $PSScriptRoot '../Invoke-Extension.ps1'
    if (Test-Path -LiteralPath $script:Adapter) { . $script:Adapter }
    . (Join-Path $PSScriptRoot '../Git-Process.ps1')

    function Set-ExtensionFixture {
        param([string]$Path, [string]$Fault = '', [string]$InstructionPath = '.github/instructions/example.instructions.md', [string]$Identity = 'example')
        $Native = ".github/skills/$Identity"
        $Sources = [ordered]@{
            "$Native/SKILL.md" = "---`nname: $Identity`ndescription: Synthetic example.`n---`n# Example`n"
            "$Native/skill.metadata.yaml" = "id: $Identity`nversion: '1.0.0'`nfacets: [architecture]`n"
            "$Native/references/detail.md" = "# Detail`nSynthetic resource.`n"
            $InstructionPath = "# Synthetic instruction`n"
            'LICENSE' = "Synthetic notice.`n"
        }
        $Payload = @(
            foreach ($Source in $Sources.Keys) {
                $Bytes = [Text.Encoding]::UTF8.GetBytes($Sources[$Source])
                [ordered]@{
                    SourcePath = $Source; MemberPath = "payload/$Source"; Mode = '100644'
                    Size = $Bytes.Length
                    Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
                    Owners = @($Identity)
                    Reasons = @(if ($Source -ceq $InstructionPath) { @{ Kind = 'external-instruction' } })
                }
            }
        )
        $Manifest = [ordered]@{
            SchemaVersion = 1; SourceCommit = ('1' * 40)
            Root = @{ Id = $Identity; Version = '1.0.0'; Folder = $Native }
            OptionalSelections = @(); Builder = @{ Contract = 'skill-archive/1' }
            Components = @(@{ Id = $Identity; Version = '1.0.0'; NativeFolder = $Native; Reasons = @(@{ Kind = 'root' }) })
            Payload = $Payload
            GeneratedMembers = @(@{ Path = 'manifest.json'; Role = 'build-evidence'; Mode = '100644' })
            Limitations = @('Synthetic test evidence.')
        }
        if ($Fault -eq 'optional') { $Manifest.OptionalSelections = @('example/related') }
        if ($Fault -eq 'path') { $Payload[0].SourcePath = '../escape'; $Payload[0].MemberPath = 'payload/../escape' }
        if ($Fault -eq 'hash') { $Payload[0].Sha256 = '0' * 64 }
        if ($Fault -eq 'identity') { $Manifest.Root.Id = '../invalid' }
        $Archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $Entries = [ordered]@{ 'manifest.json' = ($Manifest | ConvertTo-Json -Depth 30 -Compress) }
            foreach ($Source in $Sources.Keys) { $Entries["payload/$Source"] = $Sources[$Source] }
            if ($Fault -eq 'extra') { $Entries['unexpected.txt'] = 'Unexpected' }
            foreach ($Name in $Entries.Keys) {
                $Entry = $Archive.CreateEntry($Name, [IO.Compression.CompressionLevel]::NoCompression)
                $Stream = $Entry.Open()
                try { $Stream.Write([Text.Encoding]::UTF8.GetBytes($Entries[$Name])) }
                finally { $Stream.Dispose() }
            }
        }
        finally { $Archive.Dispose() }
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

Describe 'Spec Kit extension adapter' -Tag 'Unit' {
    BeforeEach {
        $script:InputPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.zip')
        $script:Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'exposes an inert dot-sourceable adapter' {
        Test-Path -LiteralPath $script:Adapter -PathType Leaf | Should -BeTrue
        $Result = . $script:Adapter
        $Result | Should -BeNullOrEmpty
        Get-Command Invoke-SkillExtension -CommandType Function | Should -Not -BeNullOrEmpty
    }

    It 'preserves required bytes and generates a one-entry exact-version catalog' {
        $Digest = Set-ExtensionFixture $script:InputPath
        $Result = Invoke-SkillExtension -ArchivePath $script:InputPath -ArchiveSha256 $Digest -OutputDirectory $script:Destination -BaseUri 'http://127.0.0.1:8123/'
        $Result.RootId | Should -BeExactly 'example'
        $Result.RootVersion | Should -BeExactly '1.0.0'
        $Result.Command | Should -BeExactly 'speckit.example.load'
        $Catalog = [IO.File]::ReadAllText($Result.CatalogPath) | ConvertFrom-Json -AsHashtable
        $Catalog.extensions.Count | Should -Be 1
        $Catalog.extensions.example.version | Should -BeExactly '1.0.0'
        $Catalog.extensions.example.download_url | Should -BeExactly 'http://127.0.0.1:8123/example-1.0.0.zip'
        $Catalog.extensions.example.sha256 | Should -BeExactly (Get-FileHash $Result.ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $Zip = [IO.Compression.ZipFile]::OpenRead($Result.ArchivePath)
        try {
            $Zip.GetEntry('extension.yml') | Should -Not -BeNullOrEmpty
            $Zip.GetEntry('source-manifest.json') | Should -Not -BeNullOrEmpty
            $Zip.GetEntry('resources/library/.github/skills/example/references/detail.md') | Should -Not -BeNullOrEmpty
            $Reader = [IO.StreamReader]::new($Zip.GetEntry('resources/library/LICENSE').Open())
            try { $Reader.ReadToEnd() | Should -BeExactly "Synthetic notice.`n" }
            finally { $Reader.Dispose() }
            $Reader = [IO.StreamReader]::new($Zip.GetEntry('commands/load.md').Open())
            try {
                $Body = $Reader.ReadToEnd()
                $Body | Should -Match '\.specify/extensions/example/resources/library/\.github/skills/example/SKILL.md'
                $Body | Should -Match '\.github/instructions/example.instructions.md'
                $Body.Contains($PSScriptRoot) | Should -BeFalse
            }
            finally { $Reader.Dispose() }
            @($Zip.Entries | Where-Object FullName -Match 'optional|related').Count | Should -Be 0
        }
        finally { $Zip.Dispose() }
    }

    It 'loads declared external instructions without the conventional filename suffix' {
        $Digest = Set-ExtensionFixture -Path $script:InputPath -InstructionPath 'docs/policy.md'
        $Result = Invoke-SkillExtension -ArchivePath $script:InputPath -ArchiveSha256 $Digest -OutputDirectory $script:Destination -BaseUri 'http://127.0.0.1:8123/'
        $Zip = [IO.Compression.ZipFile]::OpenRead($Result.ArchivePath)
        try {
            $Reader = [IO.StreamReader]::new($Zip.GetEntry('commands/load.md').Open())
            try { $Reader.ReadToEnd() | Should -Match '\.specify/extensions/example/resources/library/docs/policy\.md' }
            finally { $Reader.Dispose() }
        }
        finally { $Zip.Dispose() }
    }

    It 'rejects incorrect artifact integrity before creating output' {
        $null = Set-ExtensionFixture $script:InputPath
        { Invoke-SkillExtension -ArchivePath $script:InputPath -ArchiveSha256 ('0' * 64) -OutputDirectory $script:Destination -BaseUri 'http://127.0.0.1:8123/' } | Should -Throw 'Input:*'
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
    }

    It 'returns exactly one CLI JSON success without interpreter diagnostics' {
        $Digest = Set-ExtensionFixture $script:InputPath
        $Cli = Invoke-LibraryProcess -Executable (Get-Process -Id $PID).Path -Arguments @(
            '-NoProfile', '-File', $script:Adapter, '-ArchivePath', $script:InputPath,
            '-ArchiveSha256', $Digest, '-OutputDirectory', $script:Destination,
            '-BaseUri', 'http://127.0.0.1:8123/'
        )
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Cli.Error | Should -BeNullOrEmpty
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.RootId | Should -BeExactly 'example'
        $Result.Command | Should -BeExactly 'speckit.example.load'
        Test-Path -LiteralPath $Result.CatalogPath -PathType Leaf | Should -BeTrue
    }

    It 'refuses linked output ancestry without writing through it' {
        $Digest = Set-ExtensionFixture $script:InputPath
        $Link = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateSymbolicLink($Link, $TestDrive)
        $TargetName = [guid]::NewGuid().ToString('N')
        $LinkedDestination = Join-Path $Link $TargetName
        { Invoke-SkillExtension -ArchivePath $script:InputPath -ArchiveSha256 $Digest -OutputDirectory $LinkedDestination -BaseUri 'http://127.0.0.1:8123/' } | Should -Throw 'Output:*'
        Test-Path -LiteralPath (Join-Path $TestDrive $TargetName) | Should -BeFalse
    }

    It 'rejects invalid source evidence before creating output: <Fault>' -ForEach @(
        @{ Fault = 'optional' }, @{ Fault = 'path' }, @{ Fault = 'hash' }, @{ Fault = 'identity' }, @{ Fault = 'extra' }
    ) {
        $Digest = Set-ExtensionFixture $script:InputPath -Fault $Fault
        { Invoke-SkillExtension -ArchivePath $script:InputPath -ArchiveSha256 $Digest -OutputDirectory $script:Destination -BaseUri 'http://127.0.0.1:8123/' } | Should -Throw 'Input:*'
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
    }

    It 'refuses existing output without changing caller content' {
        $Digest = Set-ExtensionFixture $script:InputPath
        [void][IO.Directory]::CreateDirectory($script:Destination)
        $Foreign = Join-Path $script:Destination 'foreign.txt'
        [IO.File]::WriteAllText($Foreign, 'Caller-owned')
        { Invoke-SkillExtension -ArchivePath $script:InputPath -ArchiveSha256 $Digest -OutputDirectory $script:Destination -BaseUri 'http://127.0.0.1:8123/' } | Should -Throw 'Output:*'
        [IO.File]::ReadAllText($Foreign) | Should -BeExactly 'Caller-owned'
    }

    It 'refuses non-loopback HTTP hosting before creating output' {
        $Digest = Set-ExtensionFixture $script:InputPath
        { Invoke-SkillExtension -ArchivePath $script:InputPath -ArchiveSha256 $Digest -OutputDirectory $script:Destination -BaseUri 'http://example.invalid/' } | Should -Throw 'Input:*'
        Test-Path -LiteralPath $script:Destination | Should -BeFalse
    }
}

Describe 'Shared library command' -Tag 'Unit' {
    BeforeEach {
        $Source = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.zip')
        $script:LibrarySite = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Digest = Set-ExtensionFixture $Source
        $Package = Invoke-SkillExtension -ArchivePath $Source -ArchiveSha256 $Digest -OutputDirectory $script:LibrarySite -BaseUri 'http://127.0.0.1:8123/'
        $Catalog = Get-Content -LiteralPath $Package.CatalogPath -Raw | ConvertFrom-Json -AsHashtable
        $script:LibraryIndex = Join-Path $script:LibrarySite 'library.json'
        $Index = @{ schema_version = 'skill-library/1'; skills = @{ example = @{
                    current = '1.0.0'; releases = @{ '1.0.0' = @{
                            archive = 'example-1.0.0.zip'; catalog = $Catalog.extensions.example
                        } }
                } } }
        [IO.File]::WriteAllText($script:LibraryIndex, ($Index | ConvertTo-Json -Depth 30))
        $script:LibraryWorkspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Installed = Join-Path $script:LibraryWorkspace '.specify/extensions/example'
        [void][IO.Directory]::CreateDirectory($Installed)
        [IO.Compression.ZipFile]::ExtractToDirectory($Package.ArchivePath, $Installed)
        [IO.File]::WriteAllText((Join-Path $script:LibraryWorkspace '.specify/init-options.json'), '{"ai":"copilot","ai_skills":true}')
        $ManifestHash = (Get-FileHash -LiteralPath (Join-Path $Installed 'extension.yml') -Algorithm SHA256).Hash.ToLowerInvariant()
        $Registry = @{ schema_version = '1.0'; extensions = @{ skill = @{ version = '1.0.0'; enabled = $true }; example = @{
                version = '1.0.0'; enabled = $true; manifest_hash = "sha256:$ManifestHash"
            } } }
        [IO.File]::WriteAllText((Join-Path $script:LibraryWorkspace '.specify/extensions/.registry'), ($Registry | ConvertTo-Json -Depth 10))
    }

    BeforeAll {
        $script:LibraryPython = if ($env:SKILL_LIBRARY_TEST_PYTHON) { $env:SKILL_LIBRARY_TEST_PYTHON } else { 'python3' }
        $script:LibraryEntry = Join-Path $PSScriptRoot '../Invoke-Library.py'
        function Invoke-SharedLibrary {
            param([string[]]$CommandArguments)
            return Invoke-LibraryProcess -Executable $script:LibraryPython -Arguments (@(
                    '-I', '-B', $script:LibraryEntry, '--catalog', $script:LibraryIndex,
                    '--artifacts', $script:LibrarySite, '--workspace', $script:LibraryWorkspace, '--'
                ) + $CommandArguments)
        }
    }

    It 'shows the shared command operations without a catalog or workspace mutation' {
        $Python = if ($env:SKILL_LIBRARY_TEST_PYTHON) { $env:SKILL_LIBRARY_TEST_PYTHON } else { 'python3' }
        $Cli = Invoke-LibraryProcess -Executable $Python -Arguments @(
            '-I', '-B', (Join-Path $PSScriptRoot '../Invoke-Library.py')
        )
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Action | Should -BeExactly 'Help'
        $Result.Command | Should -BeExactly '/speckit-skill-library'
        $Result.Operations | Should -Contain 'search'
        $Result.Operations | Should -Contain 'install'
        $Result.Operations | Should -Contain 'list --installed'
        $Result.Operations | Should -Contain 'load'
    }

    It 'finds canonical facets case-insensitively without installing a match' {
        $Before = @(Get-ChildItem -LiteralPath $script:LibrarySite -Force -Recurse | ForEach-Object FullName)
        $Cli = Invoke-SharedLibrary @('search', 'ARCHITECTURE')
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Action | Should -BeExactly 'Search'
        @($Result.Matches).Count | Should -Be 1
        $Result.Matches[0].Id | Should -BeExactly 'example'
        @(Get-ChildItem -LiteralPath $script:LibrarySite -Force -Recurse | ForEach-Object FullName) | Should -Be $Before
    }

    It 'shows details for an exact bare skill ID' {
        $Cli = Invoke-SharedLibrary @('example')
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Action | Should -BeExactly 'Details'
        $Result.Skill.Description | Should -BeExactly 'Synthetic example.'
    }

    It 'rejects a corrupt archive before reading discovery metadata' {
        $ArchivePath = Join-Path $script:LibrarySite 'example-1.0.0.zip'
        [IO.File]::WriteAllText($ArchivePath, 'Not a ZIP archive')
        $Cli = Invoke-SharedLibrary @('search', 'architecture')
        $Cli.ExitCode | Should -Be 2
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Message | Should -BeExactly 'Artifact: Release archive digest mismatch.'
    }

    It 'resolves an advertised or explicit release before installation: <Options>' -ForEach @(
        @{ Options = @() }, @{ Options = @('--latest') }, @{ Options = @('--version', '1.0.0') }
    ) {
        $Cli = Invoke-SharedLibrary (@('install', 'example') + $Options)
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Action | Should -BeExactly 'Selection'
        $Result.RequiresPreview | Should -BeTrue
        $Result.Selected[0].Version | Should -BeExactly '1.0.0'
        $Result.Selected[0].Sha256 | Should -Match '^[a-f0-9]{64}$'
    }

    It 'rejects conflicting version selectors before catalog access' {
        Remove-Item -LiteralPath $script:LibraryIndex
        $Cli = Invoke-SharedLibrary @('install', 'example', '--latest', '--version', '1.0.0')
        $Cli.ExitCode | Should -Be 2
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Message | Should -Match '^Arguments:'
    }

    It 'reports an unknown skill without selecting or installing a guess' {
        $Cli = Invoke-SharedLibrary @('install', 'missing')
        $Cli.ExitCode | Should -Be 2
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Message | Should -Match "Sorry, we can't find that skill"
    }

    It 'lists registered installed skills without consulting a catalog' {
        Remove-Item -LiteralPath $script:LibraryIndex
        $Cli = Invoke-SharedLibrary @('list', '--installed')
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        @($Result.Skills).Count | Should -Be 1
        $Result.Skills[0].Id | Should -BeExactly 'example'
    }

    It 'loads verified installed guidance and declared instructions without source fallback' {
        $Cli = Invoke-SharedLibrary @('load', 'example', 'Assess', 'this boundary')
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Action | Should -BeExactly 'Load'
        $Result.Request | Should -BeExactly 'Assess this boundary'
        $Result.Guidance | Should -Contain '.specify/extensions/example/resources/library/.github/skills/example/SKILL.md'
        $Result.Instructions[0].Path | Should -BeExactly '.specify/extensions/example/resources/library/.github/instructions/example.instructions.md'
        $Result.Resources | Should -Contain '.specify/extensions/example/resources/library/.github/skills/example/references/detail.md'
    }

    It 'refuses a missing or disabled installation instead of silently installing it: <State>' -ForEach @(
        @{ State = 'missing' }, @{ State = 'disabled' }
    ) {
        $RegistryPath = Join-Path $script:LibraryWorkspace '.specify/extensions/.registry'
        $Registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json -AsHashtable
        if ($State -eq 'missing') { $Registry.extensions.Remove('example') }
        else { $Registry.extensions.example.enabled = $false }
        [IO.File]::WriteAllText($RegistryPath, ($Registry | ConvertTo-Json -Depth 10))
        $Cli = Invoke-SharedLibrary @('load', 'example')
        $Cli.ExitCode | Should -Be 2
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Message | Should -Match '^NotInstalled:'
    }

    It 'refuses modified installed guidance rather than reading another copy' {
        $Entrypoint = Join-Path $script:LibraryWorkspace '.specify/extensions/example/resources/library/.github/skills/example/SKILL.md'
        [IO.File]::AppendAllText($Entrypoint, 'Changed')
        $Cli = Invoke-SharedLibrary @('load', 'example')
        $Cli.ExitCode | Should -Be 2
        $Result = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Result.Message | Should -Match '^Workspace:'
        [IO.File]::ReadAllText($Entrypoint) | Should -Match 'Changed$'
    }

    It 'packages a genuine shared-command bootstrap with its backend and exact release artifacts' {
        $Source = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.zip')
        $Digest = Set-ExtensionFixture -Path $Source -Identity 'skill-library'
        $Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Package = Invoke-SkillExtension -ArchivePath $Source -ArchiveSha256 $Digest -OutputDirectory $Destination -BaseUri 'http://127.0.0.1:8123/' -LibraryCatalogPath @((Join-Path $script:LibrarySite 'catalog.json'))
        $Package.RootId | Should -BeExactly 'skill-library'
        $Package.RuntimeExtensionId | Should -BeExactly 'skill'
        $Package.Command | Should -BeExactly 'speckit.skill.library'
        $Catalog = Get-Content -LiteralPath $Package.CatalogPath -Raw | ConvertFrom-Json -AsHashtable
        @($Catalog.extensions.Keys) | Should -Be @('skill')
        $Zip = [IO.Compression.ZipFile]::OpenRead($Package.ArchivePath)
        try {
            $Zip.GetEntry('commands/library.md') | Should -Not -BeNullOrEmpty
            $Zip.GetEntry('commands/load.md') | Should -BeNullOrEmpty
            $Zip.GetEntry('tools/Invoke-Library.py') | Should -Not -BeNullOrEmpty
            $Zip.GetEntry('tools/Invoke-SpecKitInstall.py') | Should -Not -BeNullOrEmpty
            $Zip.GetEntry('tools/Read-Metadata.py') | Should -Not -BeNullOrEmpty
            $Zip.GetEntry('library/packages/example-1.0.0.zip') | Should -Not -BeNullOrEmpty
            $Reader = [IO.StreamReader]::new($Zip.GetEntry('library/catalog.json').Open())
            try { $Index = $Reader.ReadToEnd() | ConvertFrom-Json -AsHashtable }
            finally { $Reader.Dispose() }
            $Index.skills.example.current | Should -BeExactly '1.0.0'
        }
        finally { $Zip.Dispose() }
        $Extracted = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [IO.Compression.ZipFile]::ExtractToDirectory($Package.ArchivePath, $Extracted)
        $Probe = @(
            'import json, sys'
            'from pathlib import Path'
            'from specify_cli.agents import CommandRegistrar'
            'from specify_cli.extensions import ExtensionManifest'
            'manifest = ExtensionManifest(Path(sys.argv[1]) / "extension.yml")'
            'names = [CommandRegistrar._compute_output_name("copilot", command["name"], {"extension": "/SKILL.md"}) for command in manifest.commands]'
            'print(json.dumps({"Id": manifest.id, "Names": names, "Warnings": manifest.warnings}))'
        ) -join "`n"
        $Cli = Invoke-LibraryProcess -Executable $script:LibraryPython -Arguments @('-I', '-B', '-c', $Probe, $Extracted)
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Registration = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Registration.Id | Should -BeExactly 'skill'
        @($Registration.Names) | Should -Be @('speckit-skill-library')
        @($Registration.Warnings).Count | Should -Be 0
        $Cli = Invoke-LibraryProcess -Executable $script:LibraryPython -Arguments @(
            '-I', '-B', (Join-Path $Extracted 'tools/Invoke-Library.py'),
            '--workspace', $script:LibraryWorkspace, '--', 'search', 'architecture'
        )
        $Cli.ExitCode | Should -Be 0 -Because $Cli.Error
        $Discovery = [Text.Encoding]::UTF8.GetString($Cli.Bytes) | ConvertFrom-Json
        $Discovery.Action | Should -BeExactly 'Search'
        @($Discovery.Matches).Count | Should -Be 1
        $Discovery.Matches[0].Id | Should -BeExactly 'example'
    }
}
