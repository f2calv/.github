#!/usr/bin/env pwsh
#Requires -Version 7.4

BeforeAll {
    $script:Adapter = Join-Path $PSScriptRoot '../Invoke-Extension.ps1'
    if (Test-Path -LiteralPath $script:Adapter) { . $script:Adapter }
    . (Join-Path $PSScriptRoot '../Git-Process.ps1')

    function Set-ExtensionFixture {
        param([string]$Path, [string]$Fault = '', [string]$InstructionPath = '.github/instructions/example.instructions.md')
        $Native = '.github/skills/example'
        $Sources = [ordered]@{
            "$Native/SKILL.md" = "---`nname: example`ndescription: Synthetic example.`n---`n# Example`n"
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
                    Owners = @('example')
                    Reasons = @(if ($Source -ceq $InstructionPath) { @{ Kind = 'external-instruction' } })
                }
            }
        )
        $Manifest = [ordered]@{
            SchemaVersion = 1; SourceCommit = ('1' * 40)
            Root = @{ Id = 'example'; Version = '1.0.0'; Folder = $Native }
            OptionalSelections = @(); Builder = @{ Contract = 'skill-archive/1' }
            Components = @(@{ Id = 'example'; Version = '1.0.0'; NativeFolder = $Native; Reasons = @(@{ Kind = 'root' }) })
            Payload = $Payload
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
