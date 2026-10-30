#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Invoke-VersionPreparation.ps1')
    $script:Python = if ($env:SKILL_LIBRARY_TEST_PYTHON) { $env:SKILL_LIBRARY_TEST_PYTHON } else { 'python3' }
    $script:InventoryScript = Join-Path $PSScriptRoot '../Invoke-InventoryPreview.ps1'

    function Assert-InventoryFixtureRoot {
        param([string]$Root)
        $Prefix = [IO.Path]::GetFullPath($TestDrive) + [IO.Path]::DirectorySeparatorChar
        if (-not [IO.Path]::GetFullPath($Root).StartsWith($Prefix, [StringComparison]::Ordinal)) {
            throw 'Synthetic fixture operations must remain inside TestDrive.'
        }
    }

    function Invoke-InventoryGit {
        param([string]$Root, [string[]]$Arguments)
        Assert-InventoryFixtureRoot $Root
        Invoke-PreparationGit -Root $Root -Arguments $Arguments
    }

    function Set-InventoryFile {
        param([string]$Root, [string]$Path, [string]$Text = 'Synthetic content.', [byte[]]$Bytes)
        Assert-InventoryFixtureRoot $Root
        $FullPath = [IO.Path]::GetFullPath((Join-Path $Root $Path))
        $Prefix = [IO.Path]::GetFullPath($Root) + [IO.Path]::DirectorySeparatorChar
        if (-not $FullPath.StartsWith($Prefix, [StringComparison]::Ordinal)) {
            throw 'Synthetic fixture paths must remain inside their repository.'
        }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($FullPath))
        if ($PSBoundParameters.ContainsKey('Bytes')) { [IO.File]::WriteAllBytes($FullPath, $Bytes) }
        else { [IO.File]::WriteAllText($FullPath, $Text) }
    }

    function Set-InventorySkill {
        param([string]$Root, [string]$Name = 'example', [hashtable]$Fields = @{})
        $Directory = ".github/skills/$Name"
        Set-InventoryFile $Root "$Directory/SKILL.md" "---`nname: $Name`ndescription: Synthetic fixture.`n---`n# Example`n"
        $Record = [ordered]@{ id = $Name; version = '1.0.0' }
        foreach ($Key in $Fields.Keys) { $Record[$Key] = $Fields[$Key] }
        Set-InventoryFile $Root "$Directory/skill.metadata.yaml" (ConvertTo-Json $Record -Depth 32)
    }

    function Save-InventoryFixture {
        param([string]$Root, [switch]$AlreadyStaged)
        if (-not $AlreadyStaged) { [void](Invoke-InventoryGit $Root @('-c', 'core.fileMode=false', 'add', '-A')) }
        $EmptyHooks = Join-Path $Root '.git/empty-hooks'
        [void][IO.Directory]::CreateDirectory($EmptyHooks)
        [void](Invoke-InventoryGit $Root @('-c', "core.hooksPath=$EmptyHooks", '-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'Synthetic fixture'))
        Invoke-InventoryGit $Root @('rev-parse', 'HEAD')
    }

    function New-InventoryFixture {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($Root)
        $Template = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($Template)
        [void](Invoke-InventoryGit $Root @('init', '-q', "--template=$Template"))
        Set-InventoryFile $Root '.config/skill-library.yaml' "license: MIT`nnotices: [LICENSE]`n"
        Set-InventoryFile $Root 'LICENSE' "Synthetic notice.`n"
        Set-InventorySkill $Root
        [void](Save-InventoryFixture $Root)
        return $Root
    }

    function Get-InventoryState {
        param([string]$Root)
        Assert-InventoryFixtureRoot $Root
        $Files = [Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
        $Pending = [Collections.Generic.Stack[string]]::new()
        $Pending.Push($Root)
        while ($Pending.Count -gt 0) {
            foreach ($Item in Get-ChildItem -LiteralPath $Pending.Pop() -Force) {
                if ($Item.FullName -eq (Join-Path $Root '.git')) { continue }
                $Relative = [IO.Path]::GetRelativePath($Root, $Item.FullName).Replace('\', '/')
                if ($Item.LinkType) { $Files[$Relative] = "link:$($Item.LinkTarget)" }
                elseif ($Item.PSIsContainer) { $Pending.Push($Item.FullName) }
                else {
                    $Hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Item.FullName)))
                    $Mode = if ($IsWindows) { 'windows' } else { [string][IO.File]::GetUnixFileMode($Item.FullName) }
                    $Files[$Relative] = "$Mode`:$Hash"
                }
            }
        }
        $Index = Join-Path $Root '.git/index'
        $IndexHash = if ([IO.File]::Exists($Index)) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Index))) } else { '' }
        [ordered]@{
            Files = $Files
            Index = $IndexHash
            Head = [IO.File]::ReadAllText((Join-Path $Root '.git/HEAD'))
            Refs = Invoke-InventoryGit $Root @('for-each-ref', '--format=%(refname) %(objectname)')
            Config = [IO.File]::ReadAllText((Join-Path $Root '.git/config'))
        } | ConvertTo-Json -Depth 32 -Compress
    }

    function Invoke-PreviewFixture {
        param([string[]]$Names = @(), [string[]]$Selections = @(), [string]$Revision = 'HEAD')
        Invoke-SkillInventoryPreview -RepoRoot $script:Root -SkillName $Names -OptionalSelection $Selections -SourceRevision $Revision -PythonPath $script:Python
    }

    function Invoke-PreviewFixtureCli {
        param([string[]]$AdditionalArguments = @())
        $InterpreterArguments = if ('-PythonPath' -in $AdditionalArguments) { @() } else { @('-PythonPath', $script:Python) }
        Invoke-LibraryProcess -Executable (Get-Process -Id $PID).Path -Arguments (@(
            '-NoProfile', '-File', $script:InventoryScript, '-RepoRoot', $script:Root
        ) + $InterpreterArguments + $AdditionalArguments)
    }
}

Describe 'Inventory synthetic fixtures' -Tag 'Unit' {
    It 'creates a committed library and preserves binary resources' {
        $Root = New-InventoryFixture
        Set-InventoryFile -Root $Root -Path '.github/skills/example/assets/data.bin' -Bytes ([byte[]]@(0, 255, 13, 10, 128))
        $Commit = Save-InventoryFixture $Root
        $Commit | Should -Match '^[0-9a-f]{40,64}$'
        (Invoke-InventoryGit $Root @('ls-tree', '-r', '--name-only', 'HEAD')) | Should -Match 'assets/data.bin'
        [IO.File]::ReadAllBytes((Join-Path $Root '.github/skills/example/assets/data.bin')) | Should -Be ([byte[]]@(0, 255, 13, 10, 128))
    }

    It 'supports required and explicitly selected optional graph declarations' {
        $Root = New-InventoryFixture
        Set-InventorySkill $Root 'leaf'
        Set-InventorySkill $Root 'optional' @{ required = @(@{ id = 'leaf'; version = '1.0.0' }) }
        Set-InventorySkill $Root 'example' @{ optional = @(@{ id = 'optional'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic choice.' }) }
        [void](Save-InventoryFixture $Root)
        $Result = Invoke-SkillValidation -RepoRoot $Root -SkillName example -OptionalSelection example/extra -PythonPath $script:Python
        $Result.SelectedIds -join ',' | Should -Be 'leaf,optional,example'
    }

    It 'detects tracked, untracked, index and ref changes without refreshing the index' {
        $Root = New-InventoryFixture
        $Before = Get-InventoryState $Root
        (Get-InventoryState $Root) | Should -BeExactly $Before
        Set-InventoryFile $Root 'untracked.txt'
        (Get-InventoryState $Root) | Should -Not -BeExactly $Before
        [IO.File]::Delete((Join-Path $Root 'untracked.txt'))
        (Get-InventoryState $Root) | Should -BeExactly $Before
        Set-InventoryFile $Root 'LICENSE' 'Changed synthetic notice.'
        (Get-InventoryState $Root) | Should -Not -BeExactly $Before
        $Dirty = Get-InventoryState $Root
        [void](Invoke-InventoryGit $Root @('add', 'LICENSE'))
        (Get-InventoryState $Root) | Should -Not -BeExactly $Dirty
        $Staged = Get-InventoryState $Root
        [void](Invoke-InventoryGit $Root @('tag', 'synthetic/1.0.0'))
        (Get-InventoryState $Root) | Should -Not -BeExactly $Staged
    }

    It 'rejects fixture writes outside their temporary repository' {
        $Root = New-InventoryFixture
        { Set-InventoryFile $Root '../escape.txt' } | Should -Throw '*inside their repository*'
        { Invoke-InventoryGit (Split-Path $TestDrive -Parent) @('status') } | Should -Throw '*inside TestDrive*'
    }
}

Describe 'Inventory snapshot boundary' -Tag 'Unit' {
    BeforeAll {
        . $script:InventoryScript
        function Invoke-SnapshotFixture {
            param([string]$Revision = 'HEAD', [string[]]$Names = @(), [scriptblock]$Inspect = {
                param($Snapshot)
                [pscustomobject]@{ Commit = $Snapshot.Commit; Paths = @($Snapshot.Eligible); Scratch = $Snapshot.Scratch }
            })
            Invoke-InventoryInspection -RepoRoot $script:Root -SourceRevision $Revision -SkillName $Names -PythonPath $script:Python -Inspect $Inspect
        }
    }

    BeforeEach { $script:Root = New-InventoryFixture }

    It 'uses committed skill exclusions before reading upstream sidecars' {
        Set-InventorySkill $script:Root 'speckit-example'
        Set-InventoryFile $script:Root '.github/skills/speckit-example/skill.metadata.yaml' 'invalid: ['
        Set-InventoryFile $script:Root '.skillsignore' "speckit-*`n"
        [void](Save-InventoryFixture $script:Root)
        Set-InventoryFile $script:Root '.skillsignore' 'invalid/**'
        $Result = Invoke-SnapshotFixture
        $Result.Paths | Should -Contain '.skillsignore'
        @($Result.Paths | Where-Object { $_ -like '.github/skills/speckit-*/*' }).Count | Should -Be 0
    }

    It 'reads committed binary bytes despite dirty, deleted and untracked files without changing source state' {
        Set-InventoryFile -Root $script:Root -Path '.github/skills/example/assets/data.bin' -Bytes ([byte[]]@(0, 255, 13, 10, 128))
        $Commit = Save-InventoryFixture $script:Root
        Set-InventoryFile $script:Root '.github/skills/example/skill.metadata.yaml' 'Invalid local metadata.'
        [IO.File]::Delete((Join-Path $script:Root '.github/skills/example/assets/data.bin'))
        Set-InventoryFile $script:Root '.github/skills/example/untracked.txt'
        $Before = Get-InventoryState $script:Root
        $Result = Invoke-SnapshotFixture -Inspect {
            param($Snapshot)
            [pscustomobject]@{
                Commit = $Snapshot.Commit; Paths = @($Snapshot.Eligible); Scratch = $Snapshot.Scratch
                Bytes = [IO.File]::ReadAllBytes((Join-Path $Snapshot.Data '.github/skills/example/assets/data.bin'))
            }
        }
        $Result.Commit | Should -BeExactly $Commit
        $Result.Bytes | Should -Be ([byte[]]@(0, 255, 13, 10, 128))
        $Result.Paths | Should -Not -Contain '.github/skills/example/untracked.txt'
        Test-Path -LiteralPath $Result.Scratch | Should -BeFalse
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'uses current trusted tooling instead of historical scripts and imports' {
        Set-InventoryFile $script:Root '.github/skills/skill-library/scripts/Read-Metadata.py' 'raise SystemExit("SYNTHETIC_HISTORICAL_TOOL")'
        Set-InventoryFile $script:Root '.github/skills/skill-library/skill-metadata.schema.json' '{}'
        Set-InventoryFile $script:Root '.github/skills/example/yaml.py' 'raise SystemExit("SYNTHETIC_HISTORICAL_IMPORT")'
        Set-InventoryFile $script:Root '.github/skills/example/sitecustomize.py' 'raise SystemExit("SYNTHETIC_HISTORICAL_IMPORT")'
        [void](Save-InventoryFixture $script:Root)
        $Result = Invoke-SnapshotFixture
        $Result.Paths | Should -Not -Contain '.github/skills/skill-library/scripts/Read-Metadata.py'
        $Result.Paths | Should -Contain '.github/skills/example/yaml.py'
        Test-Path -LiteralPath $Result.Scratch | Should -BeFalse
    }

    It 'validates unselected opted-in records before producing a closure' {
        Set-InventorySkill $script:Root 'other' @{ unexpected = $true }
        [void](Save-InventoryFixture $script:Root)
        $Before = Get-InventoryState $script:Root
        { Invoke-SnapshotFixture -Names example } | Should -Throw '*Validation:*'
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'uses committed nested ignore negation rather than working or host excludes' {
        Set-InventoryFile $script:Root '.gitignore' '*.scratch'
        Set-InventoryFile $script:Root '.github/skills/example/.gitignore' '!keep.scratch'
        Set-InventoryFile $script:Root '.github/skills/example/drop.scratch'
        Set-InventoryFile $script:Root '.github/skills/example/keep.scratch'
        [void](Invoke-InventoryGit $script:Root @('add', '-f', '.github/skills/example/drop.scratch'))
        [void](Save-InventoryFixture $script:Root)
        Set-InventoryFile $script:Root '.gitignore' '*'
        Set-InventoryFile $script:Root '.git/info/exclude' '*'
        $Result = Invoke-SnapshotFixture
        $Result.Paths | Should -Not -Contain '.github/skills/example/drop.scratch'
        $Result.Paths | Should -Contain '.github/skills/example/keep.scratch'
        $Result.Paths | Should -Contain '.github/skills/example/SKILL.md'
    }

    It 'fails ignored mandatory <Path> rather than dropping it' -ForEach @(
        @{ Path = '.github/skills/example/skill.metadata.yaml' }
        @{ Path = '.github/skills/example/SKILL.md' }
        @{ Path = 'LICENSE' }
        @{ Path = 'external.md' }
    ) {
        Set-InventoryFile $script:Root 'external.md'
        Set-InventorySkill $script:Root 'example' @{ externalFiles = @(@{ path = 'external.md'; kind = 'instruction'; loadingPurpose = 'Synthetic.' }) }
        Set-InventoryFile $script:Root '.gitignore' "/$Path"
        [void](Invoke-InventoryGit $script:Root @('add', '-f', 'external.md'))
        [void](Save-InventoryFixture $script:Root)
        $Before = Get-InventoryState $script:Root
        { Invoke-SnapshotFixture } | Should -Throw '*Eligibility:*'
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'rejects unavailable and ambiguous revisions without native diagnostics' {
        [void](Invoke-InventoryGit $script:Root @('branch', 'ambiguous'))
        [void](Invoke-InventoryGit $script:Root @('tag', 'ambiguous'))
        foreach ($Revision in @('ambiguous', 'missing-synthetic-revision', '--help')) {
            { Invoke-SnapshotFixture -Revision $Revision } | Should -Throw '*Source:*'
        }
    }

    It 'rejects unsafe opted-in links even when snapshot rules ignore them' -Skip:$IsWindows {
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $script:Root '.github/skills/example/linked') -Target '../../../LICENSE')
        Set-InventoryFile $script:Root '.gitignore' 'linked'
        [void](Invoke-InventoryGit $script:Root @('add', '-f', '.github/skills/example/linked'))
        [void](Save-InventoryFixture $script:Root)
        { Invoke-SnapshotFixture } | Should -Throw '*Inspection:*'
    }

    It 'removes temporary contexts after callback failure without leaking its contents' {
        $script:ObservedScratch = $null
        $Before = Get-InventoryState $script:Root
        { Invoke-SnapshotFixture -Inspect {
                param($Snapshot)
                $script:ObservedScratch = $Snapshot.Scratch
                throw 'SYNTHETIC_PRIVATE_PAYLOAD'
            } } | Should -Throw '*Inspection:*'
        $script:ObservedScratch | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:ObservedScratch | Should -BeFalse
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }
}

Describe 'Inventory required preview' -Tag 'Unit' {
    BeforeAll { . $script:InventoryScript }
    BeforeEach { $script:Root = New-InventoryFixture }

    It 'dot-sources inertly and exposes only the five declared preview parameters and their defaults' {
        $Output = @(. $script:InventoryScript -RepoRoot (Join-Path $TestDrive 'missing-source'))
        $Output.Count | Should -Be 0
        $Command = Get-Command Invoke-SkillInventoryPreview
        ($Command.Parameters.Keys | Sort-Object) -join ',' | Should -Be 'OptionalSelection,PythonPath,RepoRoot,SkillName,SourceRevision'
        $Defaults = @{}
        foreach ($Parameter in $Command.ScriptBlock.Ast.Body.ParamBlock.Parameters) {
            $Defaults[$Parameter.Name.VariablePath.UserPath] = $Parameter.DefaultValue.Extent.Text
        }
        $Defaults.SourceRevision | Should -BeExactly "'HEAD'"
        $Defaults.PythonPath | Should -BeExactly "'python3'"
        $Defaults.SkillName | Should -BeExactly '@()'
        $Defaults.OptionalSelection | Should -BeExactly '@()'
        $Defaults.RepoRoot | Should -Match 'PSScriptRoot.*\.\./\.\./\.\./\.\.'
    }

    It 'reports the exact required closure and committed files with source modes and every incoming reason' {
        Set-InventorySkill $script:Root 'leaf'
        Set-InventorySkill $script:Root 'dependency' @{ required = @(@{ id = 'leaf'; version = '1.0.0' }) }
        Set-InventorySkill $script:Root 'example' @{ required = @(@{ id = 'dependency'; version = '1.0.0' }) }
        Set-InventoryFile -Root $script:Root -Path '.github/skills/leaf/data.bin' -Bytes ([byte[]]@(0, 255, 128))
        [void](Invoke-InventoryGit $script:Root @('add', '-A'))
        [void](Invoke-InventoryGit $script:Root @('update-index', '--chmod=+x', '.github/skills/leaf/data.bin'))
        $Commit = Save-InventoryFixture $script:Root
        $Before = Get-InventoryState $script:Root
        $Result = Invoke-PreviewFixture -Names example
        ($Result.Components.Id -join ',') | Should -BeExactly 'dependency,example,leaf'
        $Result.SourceCommit | Should -BeExactly $Commit
        $Result.ValidationRules | Should -BeExactly 'invoked-tool-bundle'
        $Result.Roots -join ',' | Should -BeExactly 'example'
        $Expected = @('LICENSE', '.github/skills/leaf/data.bin')
        foreach ($Id in @('dependency', 'example', 'leaf')) { $Expected += ".github/skills/$Id/SKILL.md", ".github/skills/$Id/skill.metadata.yaml" }
        ($Result.Files.Path -join ',') | Should -BeExactly ((Get-InventoryOrder $Expected) -join ',')
        @($Result.Files | Where-Object SourceCommit -CNE $Commit).Count | Should -Be 0
        @($Result.Components | Where-Object SourceCommit -CNE $Commit).Count | Should -Be 0
        $Leaf = $Result.Components | Where-Object Id -EQ leaf
        $Leaf.RootIds -join ',' | Should -BeExactly 'example'
        $Leaf.Reasons[0].FromId | Should -BeExactly 'dependency'
        $Leaf.Reasons[0].ToId | Should -BeExactly 'leaf'
        $Leaf.Reasons[0].Kind | Should -BeExactly 'required'
        $Leaf.Reasons[0].Field | Should -BeExactly 'required[0]'
        $Leaf.NativeFolder | Should -BeExactly '.github/skills/leaf'
        $Leaf.Entrypoint | Should -BeExactly '.github/skills/leaf/SKILL.md'
        $Binary = $Result.Files | Where-Object Path -EQ '.github/skills/leaf/data.bin'
        $Binary.Mode | Should -BeExactly '100755'
        $Binary.Owners -join ',' | Should -BeExactly 'leaf'
        $Binary.Reasons[0].Kind | Should -BeExactly 'internal-content'
        $Binary.Reasons[0].Field | Should -BeExactly 'implicit-directory'
        ($Result.Components | Where-Object Id -EQ example).Reasons[0].Kind | Should -BeExactly 'root'
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'defaults to the invoked tool repository independently of the caller directory' {
        $Bundle = Join-Path $script:Root '.github/skills/skill-library'
        foreach ($Path in @('scripts/Invoke-InventoryPreview.ps1', 'scripts/Invoke-Validation.ps1', 'scripts/Git-Process.ps1', 'scripts/Read-Metadata.py', 'skill-metadata.schema.json', 'repository-defaults.schema.json')) {
            $Target = Join-Path $Bundle $Path
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
            [IO.File]::Copy((Join-Path $PSScriptRoot "../../$Path"), $Target)
        }
        [void](Save-InventoryFixture $script:Root)
        $Before = Get-InventoryState $script:Root
        $CopiedScript = Join-Path $Bundle 'scripts/Invoke-InventoryPreview.ps1'
        Push-Location $TestDrive
        try {
            . $CopiedScript
            (Invoke-SkillInventoryPreview -PythonPath $script:Python).Components.Id -join ',' | Should -BeExactly 'example'
            $Result = Invoke-LibraryProcess -Executable (Get-Process -Id $PID).Path -Arguments @('-NoProfile', '-File', $CopiedScript, '-PythonPath', $script:Python)
            $Result.ExitCode | Should -Be 0
            $Object = ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($Result.Bytes))
            $Object.Components.Id -join ',' | Should -BeExactly 'example'
        }
        finally { Pop-Location }
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'normalizes repeated roots, expands omitted roots and preserves empty and singleton arrays' {
        Set-InventorySkill $script:Root 'other'
        [void](Save-InventoryFixture $script:Root)
        $Repeated = Invoke-PreviewFixture -Names example,example
        $Single = Invoke-PreviewFixture -Names example
        (ConvertTo-Json $Repeated -Depth 64 -Compress) | Should -BeExactly (ConvertTo-Json $Single -Depth 64 -Compress)
        $All = Invoke-PreviewFixture
        $All.Roots -join ',' | Should -BeExactly 'example,other'
        $All.Components.Id -join ',' | Should -BeExactly 'example,other'
        foreach ($Value in @($Single.Roots, $Single.OptionalSelections, $Single.Components, $Single.Files, $Single.Components[0].RootIds, $Single.Components[0].Reasons, $Single.Components[0].Notices)) {
            ($Value -is [array]) | Should -BeTrue
        }
        $Single.Components[0].License.Value | Should -BeExactly 'MIT'
        $Single.Limitations -join ' ' | Should -Match 'local (changes|edits).*excluded'
        $Single.Limitations -join ' ' | Should -Match 'not.*package'
        $Single.Limitations -join ' ' | Should -Match 'rights'
    }

    It 'uses the requested historical commit and ignores local-only metadata and notices' {
        $Commit = Invoke-InventoryGit $script:Root @('rev-parse', 'HEAD')
        Set-InventorySkill $script:Root 'later'
        [void](Save-InventoryFixture $script:Root)
        Set-InventorySkill $script:Root 'untracked'
        [IO.File]::Delete((Join-Path $script:Root 'LICENSE'))
        $Before = Get-InventoryState $script:Root
        $Result = Invoke-PreviewFixture -Revision $Commit
        $Result.Components.Id -join ',' | Should -BeExactly 'example'
        $Result.SourceCommit | Should -BeExactly $Commit
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'emits one complete JSON object to stdout with no native diagnostics' {
        $Result = Invoke-PreviewFixtureCli
        $Result.ExitCode | Should -Be 0
        $Result.Error | Should -BeNullOrEmpty
        $Json = [Text.Encoding]::UTF8.GetString($Result.Bytes)
        $Object = ConvertFrom-Json $Json -AsHashtable
        $Object.Components.Count | Should -Be 1
        ($Object.Roots -is [array]) | Should -BeTrue
        ($Object.OptionalSelections -is [array]) | Should -BeTrue
        ($Object.Components[0].RootIds -is [array]) | Should -BeTrue
        $Json | Should -Not -Match 'skill-inventory-|SYNTHETIC|Traceback|Payload|Digest|Timestamp'
    }

    It 'fails unknown and unconverted roots without partial stdout or host exit' {
        Set-InventoryFile $script:Root '.github/skills/unconverted/SKILL.md'
        [void](Save-InventoryFixture $script:Root)
        foreach ($Name in @('unknown', 'unconverted')) {
            { Invoke-PreviewFixture -Names $Name } | Should -Throw '*Validation:*'
            $Result = Invoke-PreviewFixtureCli @('-SkillName', $Name)
            $Result.ExitCode | Should -Be 1
            $Result.Bytes.Length | Should -Be 0
            $Result.Error | Should -Match 'Validation:'
            $Result.Error | Should -Not -Match ([regex]::Escape($script:Root))
        }
        (Invoke-PreviewFixture -Names example).Components.Count | Should -Be 1
    }

    It 'suppresses success on cleanup failure and sanitizes seeded failure details' {
        $script:CleanupPath = $null
        Mock Remove-InventoryScratch {
            param($Path)
            $script:CleanupPath = $Path
            throw 'SYNTHETIC_PRIVATE_CLEANUP'
        }
        $Before = Get-InventoryState $script:Root
        try {
            $script:Partial = @()
            { $script:Partial = @(Invoke-PreviewFixture) } | Should -Throw '*Cleanup:*'
            $script:Partial.Count | Should -Be 0
            $script:CleanupPath | Should -Not -BeNullOrEmpty
            (Get-InventoryState $script:Root) | Should -BeExactly $Before
        }
        finally { if ($script:CleanupPath -and [IO.Directory]::Exists($script:CleanupPath)) { [IO.Directory]::Delete($script:CleanupPath, $true) } }
    }

    It 'fails missing local prerequisites without leaking executable or source paths' {
        $Result = Invoke-PreviewFixtureCli @('-PythonPath', (Join-Path $TestDrive 'missing-python'))
        $Result.ExitCode | Should -Be 1
        $Result.Bytes.Length | Should -Be 0
        $Result.Error | Should -Match 'Prerequisite:'
        $Result.Error | Should -Not -Match ([regex]::Escape($TestDrive))
    }
}

Describe 'Inventory optional attribution' -Tag 'Unit' {
    BeforeAll { . $script:InventoryScript }
    BeforeEach { $script:Root = New-InventoryFixture }

    It 'adds only explicit reachable optionals, their requirements and explicitly selected nested edges' {
        Set-InventorySkill $script:Root 'leaf'
        Set-InventorySkill $script:Root 'nested'
        Set-InventorySkill $script:Root 'optional' @{
            required = @(@{ id = 'leaf'; version = '1.0.0' })
            optional = @(@{ id = 'nested'; version = '1.0.0'; selectionKey = 'nested'; reason = 'Synthetic nested choice.' })
        }
        Set-InventorySkill $script:Root 'example' @{ optional = @(@{ id = 'optional'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic choice.' }) }
        [void](Save-InventoryFixture $script:Root)
        (Invoke-PreviewFixture -Names example).Components.Id -join ',' | Should -BeExactly 'example'
        $Chosen = Invoke-PreviewFixture -Names example -Selections example/extra
        $Chosen.Components.Id -join ',' | Should -BeExactly 'example,leaf,optional'
        $Optional = $Chosen.Components | Where-Object Id -EQ optional
        $Optional.RootIds -join ',' | Should -BeExactly 'example'
        $Optional.Reasons[0].Kind | Should -BeExactly 'optional'
        $Optional.Reasons[0].FromId | Should -BeExactly 'example'
        $Optional.Reasons[0].SelectionKey | Should -BeExactly 'extra'
        $Optional.Reasons[0].Field | Should -BeExactly 'optional[0]'
        $Nested = Invoke-PreviewFixture -Names example -Selections optional/nested,example/extra
        $Nested.Components.Id -join ',' | Should -BeExactly 'example,leaf,nested,optional'
        $Nested.OptionalSelections -join ',' | Should -BeExactly 'example/extra,optional/nested'
        ($Nested.Components | Where-Object Id -EQ nested).RootIds -join ',' | Should -BeExactly 'example'
        $Reverse = Invoke-PreviewFixture -Names example -Selections example/extra,optional/nested
        (ConvertTo-Json $Nested -Depth 64 -Compress) | Should -BeExactly (ConvertTo-Json $Reverse -Depth 64 -Compress)
    }

    It 'retains all diamond roots and incoming edges while deduplicating mixed internal and external files' {
        Set-InventorySkill $script:Root 'leaf'
        Set-InventoryFile $script:Root '.github/skills/leaf/shared.md'
        Set-InventorySkill $script:Root 'left' @{ required = @(@{ id = 'leaf'; version = '1.0.0' }) }
        Set-InventorySkill $script:Root 'right' @{
            required = @(@{ id = 'leaf'; version = '1.0.0' })
            externalFiles = @(@{ path = '.github/skills/leaf/shared.md'; kind = 'instruction'; loadingPurpose = 'Synthetic shared rule.' })
        }
        Set-InventorySkill $script:Root 'other' @{ required = @(@{ id = 'right'; version = '1.0.0' }) }
        Set-InventorySkill $script:Root 'example' @{
            required = @(@{ id = 'left'; version = '1.0.0' })
            optional = @(@{ id = 'right'; version = '1.0.0'; selectionKey = 'right'; reason = 'Synthetic diamond.' })
        }
        [void](Save-InventoryFixture $script:Root)
        $Result = Invoke-PreviewFixture -Names other,example -Selections example/right
        $Result.Components.Id -join ',' | Should -BeExactly 'example,leaf,left,other,right'
        $Leaf = $Result.Components | Where-Object Id -EQ leaf
        $Leaf.RootIds -join ',' | Should -BeExactly 'example,other'
        $Leaf.Reasons.FromId -join ',' | Should -BeExactly 'left,right'
        $Right = $Result.Components | Where-Object Id -EQ right
        $Right.RootIds -join ',' | Should -BeExactly 'example,other'
        $Right.Reasons.Kind -join ',' | Should -BeExactly 'optional,required'
        $Shared = @($Result.Files | Where-Object Path -EQ '.github/skills/leaf/shared.md')
        $Shared.Count | Should -Be 1
        $Shared[0].Owners -join ',' | Should -BeExactly 'leaf,right'
        $Shared[0].Reasons.Kind -join ',' | Should -BeExactly 'internal-content,external-instruction'
        ($Result.Files | Where-Object Path -EQ LICENSE).Owners -join ',' | Should -BeExactly 'example,leaf,left,other,right'
        $Repeat = Invoke-PreviewFixture -Names example,other,example -Selections example/right
        (ConvertTo-Json $Result -Depth 64 -Compress) | Should -BeExactly (ConvertTo-Json $Repeat -Depth 64 -Compress)
    }

    It 'rejects <Kind> optional requests without deduplicating them before validation' -ForEach @(
        @{ Kind = 'unknown'; Selections = @('example/unknown') }
        @{ Kind = 'duplicate'; Selections = @('example/extra', 'example/extra') }
        @{ Kind = 'unreachable'; Selections = @('other/extra') }
    ) {
        Set-InventorySkill $script:Root 'leaf'
        Set-InventorySkill $script:Root 'other' @{ optional = @(@{ id = 'leaf'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic.' }) }
        Set-InventorySkill $script:Root 'example' @{ optional = @(@{ id = 'leaf'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic.' }) }
        [void](Save-InventoryFixture $script:Root)
        $Before = Get-InventoryState $script:Root
        { Invoke-PreviewFixture -Names example -Selections $Selections } | Should -Throw '*Validation:*'
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'preserves selected-cycle rejection and allowed unselected optional cycles' {
        Set-InventorySkill $script:Root 'other' @{ optional = @(@{ id = 'example'; version = '1.0.0'; selectionKey = 'back'; reason = 'Synthetic.' }) }
        Set-InventorySkill $script:Root 'example' @{ optional = @(@{ id = 'other'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic.' }) }
        [void](Save-InventoryFixture $script:Root)
        (Invoke-PreviewFixture -Names example).Components.Id -join ',' | Should -BeExactly 'example'
        (Invoke-PreviewFixture -Names example -Selections example/extra).Components.Id -join ',' | Should -BeExactly 'example,other'
        { Invoke-PreviewFixture -Names example -Selections example/extra,other/back } | Should -Throw '*Validation:*'
    }

    It 'rejects exact-pin mismatches and catalog-wide required cycles' {
        Set-InventorySkill $script:Root 'other'
        Set-InventorySkill $script:Root 'example' @{ required = @(@{ id = 'other'; version = '2.0.0' }) }
        [void](Save-InventoryFixture $script:Root)
        { Invoke-PreviewFixture -Names example } | Should -Throw '*Validation:*'
        Set-InventorySkill $script:Root 'example' @{ required = @(@{ id = 'other'; version = '1.0.0' }) }
        Set-InventorySkill $script:Root 'other' @{ required = @(@{ id = 'example'; version = '1.0.0' }) }
        [void](Save-InventoryFixture $script:Root)
        { Invoke-PreviewFixture -Names example } | Should -Throw '*Validation:*'
    }
}

Describe 'Inventory declaration provenance' -Tag 'Unit' {
    BeforeAll { . $script:InventoryScript }
    BeforeEach { $script:Root = New-InventoryFixture }

    It 'reports <Label> license declaration sources rather than comparing effective values' -ForEach @(
        @{ Label = 'inherited'; Fields = @{}; Value = 'MIT'; Origin = 'repository-default'; Source = '.config/skill-library.yaml' }
        @{ Label = 'equal override'; Fields = @{ license = 'MIT' }; Value = 'MIT'; Origin = 'component'; Source = '.github/skills/example/skill.metadata.yaml' }
        @{ Label = 'different override'; Fields = @{ license = 'Apache-2.0' }; Value = 'Apache-2.0'; Origin = 'component'; Source = '.github/skills/example/skill.metadata.yaml' }
    ) {
        Set-InventorySkill $script:Root 'example' $Fields
        [void](Save-InventoryFixture $script:Root)
        $Before = Get-InventoryState $script:Root
        $License = (Invoke-PreviewFixture).Components[0].License
        $License.Value | Should -BeExactly $Value
        $License.Origin | Should -BeExactly $Origin
        $License.SourcePath | Should -BeExactly $Source
        $License.Field | Should -BeExactly 'license'
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'retains all inherited, additive, external and internal reasons with zero-based declaration indexes' {
        Set-InventoryFile $script:Root 'NOTICE'
        Set-InventoryFile $script:Root 'external-notice.txt'
        Set-InventoryFile $script:Root 'instructions.md'
        Set-InventoryFile $script:Root '.github/skills/example/SHARED'
        Set-InventoryFile $script:Root '.config/skill-library.yaml' "license: MIT`nnotices: [LICENSE, .github/skills/example/SHARED]`n"
        $External = @(
            @{ path = 'instructions.md'; kind = 'instruction'; loadingPurpose = 'Synthetic instruction.' }
            @{ path = 'external-notice.txt'; kind = 'notice'; loadingPurpose = 'Synthetic external terms.' }
        )
        Set-InventorySkill $script:Root 'example' @{ notices = @('NOTICE'); externalFiles = $External }
        Set-InventorySkill $script:Root 'other' @{ externalFiles = $External }
        [void](Save-InventoryFixture $script:Root)
        $Result = Invoke-PreviewFixture
        $Component = $Result.Components | Where-Object Id -EQ example
        $Component.Notices.Path -join ',' | Should -BeExactly 'LICENSE,.github/skills/example/SHARED,NOTICE'
        $Component.Notices.Field -join ',' | Should -BeExactly 'notices[0],notices[1],notices[0]'
        $Component.Notices.Origin -join ',' | Should -BeExactly 'repository-default,repository-default,component'
        $Shared = $Result.Files | Where-Object Path -EQ '.github/skills/example/SHARED'
        $Shared.Owners -join ',' | Should -BeExactly 'example,other'
        $Shared.Reasons.ComponentId -join ',' | Should -BeExactly 'example,example,other'
        $Shared.Reasons.Kind -join ',' | Should -BeExactly 'inherited-notice,internal-content,inherited-notice'
        $Instruction = $Result.Files | Where-Object Path -EQ instructions.md
        $Instruction.Owners -join ',' | Should -BeExactly 'example,other'
        $Instruction.Reasons[0].Kind | Should -BeExactly 'external-instruction'
        $Instruction.Reasons[0].SourcePath | Should -BeExactly '.github/skills/example/skill.metadata.yaml'
        $Instruction.Reasons[0].Field | Should -BeExactly 'externalFiles[0]'
        $Instruction.Reasons[0].LoadingPurpose | Should -BeExactly 'Synthetic instruction.'
        $ExternalNotice = $Result.Files | Where-Object Path -EQ external-notice.txt
        $ExternalNotice.Reasons[0].Kind | Should -BeExactly 'external-notice'
        $ExternalNotice.Reasons[0].Field | Should -BeExactly 'externalFiles[1]'
        $ExternalNotice.Reasons[0].LoadingPurpose | Should -BeExactly 'Synthetic external terms.'
        $Notice = $Result.Files | Where-Object Path -EQ NOTICE
        $Notice.Reasons[0].Kind | Should -BeExactly 'component-notice'
        $Notice.Reasons[0].Field | Should -BeExactly 'notices[0]'
        $Result.Limitations -join ' ' | Should -Match 'immutable provenance.*rights clearance.*delivery approval'
    }

    It 'keeps absent notice declarations as empty arrays and derives stable identity separately from native location' {
        Set-InventoryFile $script:Root '.config/skill-library.yaml' 'license: MIT'
        Set-InventorySkill $script:Root 'example' @{ id = 'stable-example'; notices = @() }
        [void](Save-InventoryFixture $script:Root)
        $Result = Invoke-PreviewFixture -Names example
        $Result.Components[0].Id | Should -BeExactly 'stable-example'
        $Result.Components[0].NativeFolder | Should -BeExactly '.github/skills/example'
        $Result.Components[0].RootIds -join ',' | Should -BeExactly 'stable-example'
        ($Result.Components[0].Notices -is [array]) | Should -BeTrue
        $Result.Components[0].Notices.Count | Should -Be 0
        $Result.Files.Path | Should -Not -Contain 'LICENSE'
    }

    It 'fails ignored mandatory <Kind> content with unchanged source state' -ForEach @(
        @{ Kind = 'additional notice'; Fields = @{ notices = @('NOTICE') } }
        @{ Kind = 'external notice'; Fields = @{ externalFiles = @(@{ path = 'NOTICE'; kind = 'notice'; loadingPurpose = 'Synthetic.' }) } }
    ) {
        Set-InventoryFile $script:Root 'NOTICE'
        Set-InventorySkill $script:Root 'example' $Fields
        [void](Save-InventoryFixture $script:Root)
        Set-InventoryFile $script:Root '.gitignore' '/NOTICE'
        [void](Save-InventoryFixture $script:Root)
        $Before = Get-InventoryState $script:Root
        $Result = Invoke-PreviewFixtureCli
        $Result.ExitCode | Should -Be 1
        $Result.Bytes.Length | Should -Be 0
        $Result.Error | Should -Match 'Eligibility:'
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'fails missing and duplicated declarations without disclosing seeded contents' {
        Set-InventorySkill $script:Root 'example' @{ notices = @('missing-SYNTHETIC_PRIVATE_INPUT') }
        [void](Save-InventoryFixture $script:Root)
        $Result = Invoke-PreviewFixtureCli
        $Result.ExitCode | Should -Be 1
        $Result.Bytes.Length | Should -Be 0
        $Result.Error | Should -Match 'Validation:'
        $Result.Error | Should -Not -Match 'SYNTHETIC_PRIVATE_INPUT'
        Set-InventorySkill $script:Root 'example' @{ notices = @('LICENSE') }
        [void](Save-InventoryFixture $script:Root)
        { Invoke-PreviewFixture } | Should -Throw '*Validation:*'
    }
}

Describe 'Inventory safety injections' -Tag 'Unit' {
    BeforeAll { . $script:InventoryScript }
    BeforeEach { $script:Root = New-InventoryFixture }

    It 'cleans up after injected <Phase> failure without partial output or source mutation' -ForEach @(
        @{ Phase = 'blob'; Category = 'Inspection'; Command = 'Invoke-InventoryGitRead'; Filter = { $Arguments[0] -eq 'cat-file' } }
        @{ Phase = 'validation'; Category = 'Validation'; Command = 'Invoke-SkillValidation'; Filter = { $true } }
        @{ Phase = 'matcher'; Category = 'Inspection'; Command = 'Get-InventoryEligiblePaths'; Filter = { $true } }
    ) {
        $script:InjectedScratch = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock New-InventoryScratch { [void][IO.Directory]::CreateDirectory($script:InjectedScratch); return $script:InjectedScratch }
        $script:InjectionPhase = $Phase
        Mock $Command {
            if ($script:InjectionPhase -eq 'blob') { throw [IO.IOException]::new('SYNTHETIC_PRIVATE_FAILURE') }
            throw 'SYNTHETIC_PRIVATE_FAILURE'
        } -ParameterFilter $Filter
        $Before = Get-InventoryState $script:Root
        $script:Partial = @()
        { $script:Partial = @(Invoke-PreviewFixture) } | Should -Throw "*$Category`:*"
        $script:Partial.Count | Should -Be 0
        Test-Path -LiteralPath $script:InjectedScratch | Should -BeFalse
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'rejects unsafe <Kind> committed entries before materialization' -ForEach @(
        @{ Kind = 'gitlink' }
        @{ Kind = 'case collision' }
        @{ Kind = 'secret filename' }
    ) {
        if ($Kind -eq 'gitlink') {
            $Head = Invoke-InventoryGit $script:Root @('rev-parse', 'HEAD')
            [void](Invoke-InventoryGit $script:Root @('update-index', '--add', '--cacheinfo', '160000', $Head, '.github/skills/example/submodule'))
        }
        elseif ($Kind -eq 'case collision') {
            Set-InventoryFile $script:Root '.github/skills/example/UPPER.md'
            [void](Invoke-InventoryGit $script:Root @('add', '.github/skills/example/UPPER.md'))
            $Blob = Invoke-InventoryGit $script:Root @('rev-parse', 'HEAD:LICENSE')
            [void](Invoke-InventoryGit $script:Root @('-c', 'core.ignoreCase=false', 'update-index', '--add', '--cacheinfo', '100644', $Blob, '.github/skills/example/upper.md'))
        }
        else { Set-InventoryFile $script:Root '.github/skills/example/secret.key' }
        [void](Save-InventoryFixture $script:Root -AlreadyStaged:($Kind -ne 'secret filename'))
        $Before = Get-InventoryState $script:Root
        { Invoke-PreviewFixture } | Should -Throw '*Inspection:*'
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'resolves a moving ref once and continues using only the captured commit objects' {
        Set-InventorySkill $script:Root 'later'
        $Later = Save-InventoryFixture $script:Root
        $Earlier = Invoke-InventoryGit $script:Root @('rev-parse', 'HEAD~1')
        [void](Invoke-InventoryGit $script:Root @('branch', 'moving-source', $Earlier))
        $script:FrozenRoot = $script:Root
        $script:LaterCommit = $Later
        $script:OriginalRead = (Get-Command Invoke-InventoryGitRead).ScriptBlock
        Mock Invoke-InventoryGitRead {
            param($Context, $Arguments, [switch]$Bytes)
            $Output = & $script:OriginalRead -Context $Context -Arguments $Arguments -Bytes:$Bytes
            if ($Arguments[0] -eq 'rev-parse' -and $Arguments[1] -eq '--verify') {
                [void](Invoke-InventoryGit $script:FrozenRoot @('update-ref', 'refs/heads/moving-source', $script:LaterCommit))
            }
            if ($Bytes) { return ,$Output }
            return $Output
        }
        $Result = Invoke-PreviewFixture -Revision moving-source
        $Result.SourceCommit | Should -BeExactly $Earlier
        $Result.Components.Id -join ',' | Should -BeExactly 'example'
        (Invoke-InventoryGit $script:Root @('rev-parse', 'moving-source')) | Should -BeExactly $Later
    }

    It 'does not execute configured filters, fsmonitor, hooks or advisory payload tooling' {
        $Marker = Join-Path $script:Root 'executed-marker'
        $Payload = "[IO.File]::WriteAllText('$($Marker.Replace("'", "''"))', 'Synthetic execution.')"
        Set-InventoryFile $script:Root '.github/skills/example/scripts/never-run.ps1' $Payload
        Set-InventoryFile $script:Root '.github/skills/example/data.txt' 'Synthetic filtered content.'
        Set-InventoryFile $script:Root '.gitattributes' '*.txt filter=synthetic'
        Set-InventorySkill $script:Root 'example' @{ tooling = @(@{ id = 'synthetic'; versionRequirement = '1.0.0'; scope = 'consumer'; required = $true }) }
        $Executable = (Get-Process -Id $PID).Path.Replace('\', '/')
        $PayloadPath = (Join-Path $script:Root '.github/skills/example/scripts/never-run.ps1').Replace('\', '/')
        $Command = '"' + $Executable + '" -NoProfile -File "' + $PayloadPath + '"'
        Set-InventoryFile $script:Root 'synthetic-hooks/post-checkout' "#!/bin/sh`n$Command`n"
        if (-not $IsWindows) {
            [IO.File]::SetUnixFileMode((Join-Path $script:Root 'synthetic-hooks/post-checkout'), [IO.UnixFileMode]493)
        }
        [void](Invoke-InventoryGit $script:Root @('config', 'filter.synthetic.smudge', $Command))
        [void](Invoke-InventoryGit $script:Root @('config', 'core.fsmonitor', $Command))
        [void](Invoke-InventoryGit $script:Root @('config', 'core.hooksPath', (Join-Path $script:Root 'synthetic-hooks')))
        [void](Save-InventoryFixture $script:Root)
        $Before = Get-InventoryState $script:Root
        (Invoke-PreviewFixture).Files.Path | Should -Contain '.github/skills/example/data.txt'
        Test-Path -LiteralPath $Marker | Should -BeFalse
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'fails missing local blob objects without fetching or using working-file bytes' {
        Set-InventoryFile $script:Root '.github/skills/example/unavailable.bin' 'Synthetic unavailable committed blob.'
        [void](Save-InventoryFixture $script:Root)
        $Blob = Invoke-InventoryGit $script:Root @('rev-parse', 'HEAD:.github/skills/example/unavailable.bin')
        Assert-InventoryFixtureRoot $script:Root
        [IO.File]::Delete((Join-Path $script:Root ".git/objects/$($Blob.Substring(0, 2))/$($Blob.Substring(2))"))
        $Before = Get-InventoryState $script:Root
        $Result = Invoke-PreviewFixtureCli
        $Result.ExitCode | Should -Be 1
        $Result.Bytes.Length | Should -Be 0
        $Result.Error | Should -Match 'Inspection:'
        $Result.Error | Should -Not -Match 'unavailable.bin|fatal:|remote|fetch|SYNTHETIC'
        (Get-InventoryState $script:Root) | Should -BeExactly $Before
    }

    It 'ignores inherited global excludes and expands accepted root spellings to canonical native names' {
        Set-InventoryFile $script:Root 'global-excludes' '*'
        $GlobalConfig = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $ExcludePath = (Join-Path $script:Root 'global-excludes').Replace('\', '/')
        [IO.File]::WriteAllText($GlobalConfig, "[core]`nexcludesFile = $ExcludePath`n")
        $Previous = [Environment]::GetEnvironmentVariable('GIT_CONFIG_GLOBAL')
        try {
            $env:GIT_CONFIG_GLOBAL = $GlobalConfig
            $Result = Invoke-PreviewFixture -Names EXAMPLE,example
            $Result.Roots -join ',' | Should -BeExactly 'example'
            $Result.Components[0].Reasons.Count | Should -Be 1
            $Result.Files.Path | Should -Contain '.github/skills/example/SKILL.md'
        }
        finally { [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $Previous) }
    }
}
