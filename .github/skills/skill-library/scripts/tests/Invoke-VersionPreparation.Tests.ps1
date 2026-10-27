#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Invoke-VersionPreparation.ps1')
    $script:Python = if ($env:SKILL_LIBRARY_TEST_PYTHON) { $env:SKILL_LIBRARY_TEST_PYTHON } else { 'python3' }
    $script:PreparationScript = Join-Path $PSScriptRoot '../Invoke-VersionPreparation.ps1'

    function Invoke-FixtureGit {
        param([string[]]$Arguments)
        Invoke-PreparationGit -Root $script:Root -Arguments $Arguments
    }

    function Set-VersionFixtureSkill {
        param([string]$Id = 'example', [string]$Version = '1.0.0', [hashtable]$Fields = @{})
        $Folder = Join-Path $script:Root ".github/skills/$Id"
        [void][IO.Directory]::CreateDirectory($Folder)
        [IO.File]::WriteAllText((Join-Path $Folder 'SKILL.md'), "---`nname: $Id`ndescription: Synthetic fixture.`n---`n# Example`n")
        $Record = [ordered]@{ id = $Id; version = $Version }
        foreach ($Key in $Fields.Keys) { $Record[$Key] = $Fields[$Key] }
        [IO.File]::WriteAllText((Join-Path $Folder 'skill.metadata.yaml'), (ConvertTo-Json $Record -Depth 32))
    }

    function Save-VersionFixture {
        param([string[]]$Tags = @())
        [void](Invoke-FixtureGit @('add', '-A'))
        [void](Invoke-FixtureGit @('-c', 'user.name=Synthetic', '-c', 'user.email=synthetic@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'Synthetic fixture'))
        foreach ($Tag in $Tags) { [void](Invoke-FixtureGit @('tag', $Tag)) }
    }

    function Invoke-VersionFixture {
        param([hashtable]$Impact = @{}, [string[]]$Bootstrap = @(), [switch]$Apply, [string]$Fingerprint = '')
        Invoke-SkillVersionPreparation -RepoRoot $script:Root -PythonPath $script:Python -ImpactJson (ConvertTo-Json $Impact -Compress) -BootstrapId $Bootstrap -Apply:$Apply -ReviewedFingerprint $Fingerprint
    }

    function Add-VersionFixtureChange {
        param([string]$Id = 'example')
        [IO.File]::AppendAllText((Join-Path $script:Root ".github/skills/$Id/SKILL.md"), "Compatible content change.`n")
    }

    function Get-VersionFixtureMetadata {
        param([string]$Id = 'example')
        Read-SkillYaml -Path (Join-Path $script:Root ".github/skills/$Id/skill.metadata.yaml") -PythonPath $script:Python
    }
}

Describe 'Skill version preparation' -Tag 'Unit' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory((Join-Path $script:Root '.config'))
        [IO.File]::WriteAllText((Join-Path $script:Root '.config/skill-library.yaml'), "license: MIT`nnotices: [LICENSE]`n")
        [IO.File]::WriteAllText((Join-Path $script:Root 'LICENSE'), "Synthetic notice.`n")
        [void](Invoke-FixtureGit @('init', '-q'))
        Set-VersionFixtureSkill
        Save-VersionFixture
    }

    It 'shares byte-safe process input and drains stderr independently' {
        $Bytes = [byte[]]@(0, 255, 13, 10, 128)
        $Executable = (Get-Command $script:Python -CommandType Application -TotalCount 1).Source
        $Result = Invoke-LibraryProcess -Executable $Executable -Arguments @('-I', '-B', '-c', 'import sys; sys.stderr.write("synthetic diagnostic" * 8192); sys.stdout.buffer.write(sys.stdin.buffer.read())') -InputBytes $Bytes
        $Result.ExitCode | Should -Be 0
        $Result.Bytes | Should -Be $Bytes
        $Result.Error.Length | Should -BeGreaterThan 65536
    }

    It 'shares process isolation without inheriting Git redirects or optional locks' {
        $Previous = [Environment]::GetEnvironmentVariable('GIT_DIR')
        $PreviousLocks = [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS')
        try {
            $env:GIT_DIR = Join-Path $TestDrive 'missing-synthetic-git'
            $env:GIT_OPTIONAL_LOCKS = '1'
            (Invoke-FixtureGit @('rev-parse', '--verify', 'HEAD')) | Should -Match '^[0-9a-f]{40,64}$'
            $Executable = (Get-Command $script:Python -CommandType Application -TotalCount 1).Source
            $Result = Invoke-LibraryProcess -Executable $Executable -Arguments @('-I', '-B', '-c', 'import os; print(os.environ.get("GIT_OPTIONAL_LOCKS")); print(os.environ.get("GIT_ALLOW_PROTOCOL"))')
            [Text.Encoding]::UTF8.GetString($Result.Bytes).Replace("`r", '') | Should -BeExactly "0`n`n"
        }
        finally {
            if ($null -eq $Previous) { Remove-Item Env:GIT_DIR -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable('GIT_DIR', $Previous) }
            if ($null -eq $PreviousLocks) { Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', $PreviousLocks) }
        }
        [Environment]::GetEnvironmentVariable('GIT_DIR') | Should -BeExactly $Previous
        [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS') | Should -BeExactly $PreviousLocks
    }

    It 'shares subprocess failure handling without exposing native diagnostics' {
        $Executable = (Get-Command $script:Python -CommandType Application -TotalCount 1).Source
        { Invoke-PreparationProcess -Executable $Executable -Arguments @('-I', '-B', '-c', 'import sys; sys.stderr.write("SYNTHETIC_PRIVATE_DIAGNOSTIC"); sys.exit(7)') } | Should -Throw '*subprocess failed*'
        try { [void](Invoke-PreparationProcess -Executable $Executable -Arguments @('-I', '-B', '-c', 'import sys; sys.stderr.write("SYNTHETIC_PRIVATE_DIAGNOSTIC"); sys.exit(7)')) }
        catch { $_.Exception.Message | Should -Not -Match 'SYNTHETIC_PRIVATE_DIAGNOSTIC' }
    }

    It 'requires explicit bootstrap and retains initial intent without writes' {
        $Path = Join-Path $script:Root '.github/skills/example/skill.metadata.yaml'
        $Before = [IO.File]::ReadAllText($Path)
        $Incomplete = Invoke-VersionFixture
        $Incomplete.Ready | Should -BeFalse
        $Incomplete.MissingDecisions | Should -Contain 'bootstrap: example'
        { Invoke-VersionFixture -Apply -Fingerprint $Incomplete.Fingerprint } | Should -Throw '*incomplete*'
        $Plan = Invoke-VersionFixture -Bootstrap example
        $Plan.Ready | Should -BeTrue
        $Plan.Components[0].Target | Should -Be '1.0.0'
        $Plan.Components[0].ProposedTag | Should -Be 'example/1.0.0'
        $Plan.Changes.Count | Should -Be 0
        [IO.File]::ReadAllText($Path) | Should -BeExactly $Before
        (Invoke-VersionFixture -Bootstrap example -Apply -Fingerprint $Plan.Fingerprint).Applied | Should -BeTrue
    }

    It 'includes a new nonignored component and content but excludes ignored files' {
        Set-VersionFixtureSkill -Id new-skill -Version '2.3.4'
        [IO.File]::WriteAllText((Join-Path $script:Root '.gitignore'), '*.scratch')
        [IO.File]::WriteAllText((Join-Path $script:Root '.github/skills/example/ignored.scratch'), 'Ignored.')
        $Plan = Invoke-VersionFixture -Bootstrap example,new-skill
        $Plan.Components.Count | Should -Be 2
        ($Plan.Components | Where-Object Id -EQ new-skill).Target | Should -Be '2.3.4'
        $Fingerprint = $Plan.Fingerprint
        [IO.File]::WriteAllText((Join-Path $script:Root '.github/skills/example/ignored.scratch'), 'Still ignored.')
        (Invoke-VersionFixture -Bootstrap example,new-skill).Fingerprint | Should -BeExactly $Fingerprint
    }

    It 'chooses numeric 1.10.0 over 1.9.0 and requires explicit impact' {
        Set-VersionFixtureSkill -Version '1.9.0'
        Save-VersionFixture -Tags example/1.9.0
        Set-VersionFixtureSkill -Version '1.10.0'
        Save-VersionFixture -Tags example/1.10.0
        Add-VersionFixtureChange
        $Plan = Invoke-VersionFixture
        $Plan.Components[0].Baseline | Should -Be '1.10.0'
        $Plan.MissingDecisions | Should -Contain 'impact: example'
        $Plan = Invoke-VersionFixture -Impact @{ example = 'minor' }
        $Plan.Components[0].Target | Should -Be '1.11.0'
    }

    It 'uses the released baseline for explicit <Impact> targets' -ForEach @(
        @{ Impact = 'patch'; Target = '1.0.1' }
        @{ Impact = 'minor'; Target = '1.1.0' }
        @{ Impact = 'major'; Target = '2.0.0' }
    ) {
        [void](Invoke-FixtureGit @('tag', 'example/1.0.0'))
        Add-VersionFixtureChange
        (Invoke-VersionFixture -Impact @{ example = $Impact }).Components[0].Target | Should -Be $Target
    }

    It 'rejects tag metadata mismatch and noncanonical tag versions' {
        [void](Invoke-FixtureGit @('tag', 'example/2.0.0'))
        { Invoke-VersionFixture } | Should -Throw '*mismatch*'
        [void](Invoke-FixtureGit @('tag', '-d', 'example/2.0.0'))
        [void](Invoke-FixtureGit @('tag', 'example/01.0.0'))
        { Invoke-VersionFixture } | Should -Throw '*Noncanonical*'
    }

    It 'rejects ambiguous stable IDs in committed tag metadata' {
        Set-VersionFixtureSkill -Id other
        $Path = Join-Path $script:Root '.github/skills/other/skill.metadata.yaml'
        [IO.File]::WriteAllText($Path, '{"id":"example","version":"1.0.0"}')
        Save-VersionFixture -Tags example/1.0.0
        [IO.Directory]::Delete((Join-Path $script:Root '.github/skills/other'), $true)
        { Invoke-VersionFixture } | Should -Throw '*ambiguous*'
    }

    It 'rejects nonancestor release tags' {
        $Head = Invoke-FixtureGit @('rev-parse', 'HEAD')
        Save-VersionFixture -Tags example/1.0.0
        [void](Invoke-FixtureGit @('checkout', '--detach', $Head))
        { Invoke-VersionFixture } | Should -Throw '*subprocess failed*'
    }

    It 'rejects shallow and partial history without fetching' {
        $Head = Invoke-FixtureGit @('rev-parse', 'HEAD')
        [IO.File]::WriteAllText((Join-Path $script:Root '.git/shallow'), "$Head`n")
        { Invoke-VersionFixture } | Should -Throw '*Shallow*'
        [IO.File]::Delete((Join-Path $script:Root '.git/shallow'))
        [void](Invoke-FixtureGit @('config', 'remote.synthetic.promisor', 'true'))
        { Invoke-VersionFixture } | Should -Throw '*Partial*'
    }

    It 'finds stable identity across source and native renames' {
        [void](Invoke-FixtureGit @('tag', 'example/1.0.0'))
        $Old = Join-Path $script:Root '.github/skills/example'
        $New = Join-Path $script:Root '.github/skills/renamed'
        [IO.Directory]::Move($Old, $New)
        [IO.File]::WriteAllText((Join-Path $New 'SKILL.md'), "---`nname: renamed`ndescription: Synthetic fixture.`n---`n# Example`n")
        $Plan = Invoke-VersionFixture -Impact @{ example = 'major' }
        $Plan.Components[0].Baseline | Should -Be '1.0.0'
        $Plan.Components[0].Reasons | Should -Contain 'stable-ID source/native move'
        $Plan.Components[0].Target | Should -Be '2.0.0'
    }

    It 'detects <Kind> inputs' -ForEach @(
        @{ Kind = 'shared notice'; Path = 'LICENSE'; Fields = @{} }
        @{ Kind = 'defaults'; Path = '.config/skill-library.yaml'; Fields = @{} }
        @{ Kind = 'component notice'; Path = 'NOTICE'; Fields = @{ notices = @('NOTICE') } }
        @{ Kind = 'shared external'; Path = 'shared.md'; Fields = @{ externalFiles = @(@{ path = 'shared.md'; kind = 'instruction'; loadingPurpose = 'Synthetic.' }) } }
        @{ Kind = 'internal new'; Path = '.github/skills/example/new.md'; Fields = @{} }
    ) {
        Set-VersionFixtureSkill -Fields $Fields
        if ($Path -in @('NOTICE', 'shared.md')) { [IO.File]::WriteAllText((Join-Path $script:Root $Path), "Synthetic input.`n") }
        Save-VersionFixture -Tags example/1.0.0
        [IO.File]::AppendAllText((Join-Path $script:Root $Path), $(if ($Kind -eq 'defaults') { "# changed`n" } else { "Changed.`n" }))
        $Plan = Invoke-VersionFixture -Impact @{ example = 'patch' }
        $Plan.Components[0].Reasons.Count | Should -BeGreaterThan 0
        $Plan.Components[0].Target | Should -Be '1.0.1'
    }

    It 'propagates required and unselected optional chains with convergence and optional cycles once' {
        Set-VersionFixtureSkill -Id leaf
        Set-VersionFixtureSkill -Id left -Fields @{ required = @(@{ id = 'leaf'; version = '1.0.0' }) }
        Set-VersionFixtureSkill -Id right -Fields @{ optional = @(@{ id = 'leaf'; version = '1.0.0'; selectionKey = 'leaf'; reason = 'Synthetic.' }, @{ id = 'example'; version = '1.0.0'; selectionKey = 'cycle'; reason = 'Synthetic.' }) }
        Set-VersionFixtureSkill -Fields @{ required = @(@{ id = 'left'; version = '1.0.0' }); optional = @(@{ id = 'right'; version = '1.0.0'; selectionKey = 'right'; reason = 'Synthetic.' }) }
        Save-VersionFixture -Tags example/1.0.0,leaf/1.0.0,left/1.0.0,right/1.0.0
        Add-VersionFixtureChange -Id leaf
        $Incomplete = Invoke-VersionFixture -Impact @{ leaf = 'minor' }
        $Incomplete.MissingDecisions.Count | Should -Be 3
        $Impact = @{ leaf = 'minor'; left = 'patch'; right = 'patch'; example = 'minor' }
        $Plan = Invoke-VersionFixture -Impact $Impact
        $Plan.Components.Count | Should -Be 4
        @($Plan.Components | Where-Object Target -EQ '1.0.1').Count | Should -Be 2
        $Plan.Changes.Count | Should -Be 9
        (Invoke-VersionFixture -Impact $Impact -Apply -Fingerprint $Plan.Fingerprint).Applied | Should -BeTrue
        $Again = Invoke-VersionFixture -Impact $Impact
        $Again.Changes.Count | Should -Be 0
        ($Again.Components | Where-Object Id -EQ example).Target | Should -Be '1.1.0'
        (Get-VersionFixtureMetadata).optional[0].version | Should -Be '1.0.1'
    }

    It 'detects optional declaration differences without interpreting Markdown links as edges' {
        Set-VersionFixtureSkill -Id leaf
        Save-VersionFixture -Tags example/1.0.0,leaf/1.0.0
        Set-VersionFixtureSkill -Fields @{ optional = @(@{ id = 'leaf'; version = '1.0.0'; selectionKey = 'new'; reason = 'Synthetic.' }) }
        $Plan = Invoke-VersionFixture -Impact @{ example = 'minor' }
        $Plan.Components[0].Reasons.Count | Should -BeGreaterThan 0
        ($Plan.Components | Where-Object Id -EQ leaf).Reasons.Count | Should -Be 0
    }

    It 'rejects unexplained own-version drift even when coherent with all pins' {
        [void](Invoke-FixtureGit @('tag', 'example/1.0.0'))
        $Path = Join-Path $script:Root '.github/skills/example/skill.metadata.yaml'
        [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($Path).Replace('1.0.0', '1.0.1'))
        { Invoke-VersionFixture } | Should -Throw '*own-version drift*'
    }

    It 'accepts consistent prepared own versions and pins without rebumping' {
        Set-VersionFixtureSkill -Id leaf
        Set-VersionFixtureSkill -Fields @{ required = @(@{ id = 'leaf'; version = '1.0.0' }) }
        Save-VersionFixture -Tags example/1.0.0,leaf/1.0.0
        Add-VersionFixtureChange -Id leaf
        foreach ($Id in @('example', 'leaf')) {
            $Path = Join-Path $script:Root ".github/skills/$Id/skill.metadata.yaml"
            [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($Path).Replace('1.0.0', '1.0.1'))
        }
        $Plan = Invoke-VersionFixture -Impact @{ example = 'patch'; leaf = 'patch' }
        $Plan.Changes.Count | Should -Be 0
        @($Plan.Components | Where-Object Target -EQ '1.0.1').Count | Should -Be 2
    }

    It 'leaves an unchanged released component at its baseline on repeated previews' {
        [void](Invoke-FixtureGit @('tag', 'example/1.0.0'))
        $Plan = Invoke-VersionFixture
        $Plan.Ready | Should -BeTrue
        $Plan.Components[0].Reasons.Count | Should -Be 0
        $Plan.Components[0].ProposedTag | Should -BeNullOrEmpty
        (Invoke-VersionFixture).Fingerprint | Should -BeExactly $Plan.Fingerprint
    }

    It 'refuses a stale <ChangedInput> fingerprint before any metadata writes' -ForEach @(
        @{ ChangedInput = 'source' }; @{ ChangedInput = 'refs' }; @{ ChangedInput = 'decisions' }; @{ ChangedInput = 'new file' }; @{ ChangedInput = 'index' }
    ) {
        [void](Invoke-FixtureGit @('tag', 'example/1.0.0'))
        Add-VersionFixtureChange
        $Impact = @{ example = 'patch' }
        $Plan = Invoke-VersionFixture -Impact $Impact
        switch ($ChangedInput) {
            'source' { Add-VersionFixtureChange }
            'refs' { [void](Invoke-FixtureGit @('tag', 'unrelated-tag')) }
            'decisions' { $Impact.example = 'minor' }
            'new file' { [IO.File]::WriteAllText((Join-Path $script:Root '.github/skills/example/new.md'), 'New content.') }
            'index' { [void](Invoke-FixtureGit @('add', '-A')) }
        }
        $Before = [IO.File]::ReadAllText((Join-Path $script:Root '.github/skills/example/skill.metadata.yaml'))
        { Invoke-VersionFixture -Impact $Impact -Apply -Fingerprint $Plan.Fingerprint } | Should -Throw '*fingerprint*'
        [IO.File]::ReadAllText((Join-Path $script:Root '.github/skills/example/skill.metadata.yaml')) | Should -BeExactly $Before
    }

    It 'preserves comments quotes Unicode positions CRLF and unrelated fields byte for byte' {
        Set-VersionFixtureSkill -Id leaf
        $Path = Join-Path $script:Root '.github/skills/example/skill.metadata.yaml'
        $Text = "# $([char]0x03bb)`r`nid: example`r`nversion: '1.0.0' # keep`r`nfacets: [example]`r`nrequired: [{id: leaf, version: `"1.0.0`"}] # pin`r`n"
        [IO.File]::WriteAllText($Path, $Text)
        Save-VersionFixture -Tags example/1.0.0,leaf/1.0.0
        Add-VersionFixtureChange -Id leaf
        $Impact = @{ example = 'patch'; leaf = 'patch' }
        $Plan = Invoke-VersionFixture -Impact $Impact
        [void](Invoke-VersionFixture -Impact $Impact -Apply -Fingerprint $Plan.Fingerprint)
        [IO.File]::ReadAllText($Path) | Should -BeExactly $Text.Replace('1.0.0', '1.0.1')
    }

    It 'rolls back all metadata when the second write fails' {
        Set-VersionFixtureSkill -Id leaf
        Set-VersionFixtureSkill -Fields @{ required = @(@{ id = 'leaf'; version = '1.0.0' }) }
        Save-VersionFixture -Tags example/1.0.0,leaf/1.0.0
        Add-VersionFixtureChange -Id leaf
        $Impact = @{ example = 'patch'; leaf = 'patch' }
        $Plan = Invoke-VersionFixture -Impact $Impact
        $Before = @{}
        foreach ($Id in @('example', 'leaf')) { $Before[$Id] = [IO.File]::ReadAllText((Join-Path $script:Root ".github/skills/$Id/skill.metadata.yaml")) }
        $script:WriteCount = 0
        Mock Set-PreparationBytes {
            param($Stream, $Bytes)
            $script:WriteCount++
            if ($script:WriteCount -eq 2) { throw 'Synthetic write failure.' }
            $Stream.Position = 0
            $Stream.Write($Bytes, 0, $Bytes.Length)
            $Stream.SetLength($Bytes.Length)
            $Stream.Flush($true)
        }
        { Invoke-VersionFixture -Impact $Impact -Apply -Fingerprint $Plan.Fingerprint } | Should -Throw '*Synthetic write failure*'
        foreach ($Id in @('example', 'leaf')) { [IO.File]::ReadAllText((Join-Path $script:Root ".github/skills/$Id/skill.metadata.yaml")) | Should -BeExactly $Before[$Id] }
        $script:WriteCount | Should -Be 2
    }

    It 'rejects unsafe linked inputs before preparing writes' -Skip:$IsWindows {
        $Path = Join-Path $script:Root '.github/skills/example/linked.md'
        [void](New-Item -ItemType SymbolicLink -Path $Path -Target (Join-Path $script:Root 'LICENSE'))
        { Invoke-VersionFixture -Bootstrap example } | Should -Throw '*symbolic link*'
    }

    It 'binds executable modes to the reviewed fingerprint' -Skip:$IsWindows {
        $Plan = Invoke-VersionFixture -Bootstrap example
        $Path = Join-Path $script:Root '.github/skills/example/SKILL.md'
        [IO.File]::SetUnixFileMode($Path, ([IO.File]::GetUnixFileMode($Path) -bor [IO.UnixFileMode]::UserExecute))
        { Invoke-VersionFixture -Bootstrap example -Apply -Fingerprint $Plan.Fingerprint } | Should -Throw '*fingerprint*'
    }

    It 'recovers a partial failed write without leaving metadata partly prepared' {
        [void](Invoke-FixtureGit @('tag', 'example/1.0.0'))
        Add-VersionFixtureChange
        $Plan = Invoke-VersionFixture -Impact @{ example = 'patch' }
        $Path = Join-Path $script:Root '.github/skills/example/skill.metadata.yaml'
        $Before = [IO.File]::ReadAllText($Path)
        Mock Set-PreparationBytes {
            param($Stream, $Bytes)
            $Stream.Position = 0
            $Stream.Write($Bytes, 0, $Bytes.Length - 1)
            $Stream.Flush($true)
            throw 'Synthetic partial write.'
        }
        { Invoke-VersionFixture -Impact @{ example = 'patch' } -Apply -Fingerprint $Plan.Fingerprint } | Should -Throw '*Synthetic partial write*'
        [IO.File]::ReadAllText($Path) | Should -BeExactly $Before
    }

    It 'preserves unexpected concurrent metadata instead of overwriting it during rollback' {
        [void](Invoke-FixtureGit @('tag', 'example/1.0.0'))
        Add-VersionFixtureChange
        $Plan = Invoke-VersionFixture -Impact @{ example = 'patch' }
        $Path = Join-Path $script:Root '.github/skills/example/skill.metadata.yaml'
        Mock Set-PreparationBytes {
            param($Stream, $Bytes)
            $Data = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($Bytes) + "`n ")
            $Stream.Position = 0
            $Stream.Write($Data, 0, $Data.Length)
            $Stream.SetLength($Data.Length)
            $Stream.Flush($true)
        }
        $Failure = $null
        try { [void](Invoke-VersionFixture -Impact @{ example = 'patch' } -Apply -Fingerprint $Plan.Fingerprint) }
        catch { $Failure = $_.Exception }
        $Failure | Should -Not -BeNullOrEmpty
        $Failure.Message | Should -Match 'preserved'
        $RecoveryDirectory = $Failure.Data['RecoveryDirectory']
        try {
            [IO.File]::ReadAllText($Path).EndsWith("`n ") | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $RecoveryDirectory 'originals/.github/skills/example/skill.metadata.yaml') | Should -BeTrue
        }
        finally { Remove-Item -LiteralPath $RecoveryDirectory -Recurse -Force }
    }

    It 'returns JSON through the native CLI and rejects Apply without reviewed approval' {
        $Output = & pwsh -NoProfile -File $script:PreparationScript -RepoRoot $script:Root -PythonPath $script:Python -BootstrapId example 2>&1
        $LASTEXITCODE | Should -Be 0
        $Plan = ($Output -join "`n") | ConvertFrom-Json
        $Plan.Ready | Should -BeTrue
        $Plan.Applied | Should -BeFalse
        $Plan.Components[0].Target | Should -Be '1.0.0'
        $Output = & pwsh -NoProfile -File $script:PreparationScript -RepoRoot $script:Root -PythonPath $script:Python -BootstrapId example -Apply 2>&1
        $LASTEXITCODE | Should -Be 1
        ($Output -join '') | Should -Match 'fingerprint'
    }

    It 'prepares the component containing the implementation without invalidating its own approved write' {
        Set-VersionFixtureSkill -Id preparer
        $Destination = Join-Path $script:Root '.github/skills/preparer'
        [void][IO.Directory]::CreateDirectory((Join-Path $Destination 'scripts'))
        foreach ($Name in @('Invoke-Validation.ps1', 'Invoke-VersionPreparation.ps1', 'Git-Process.ps1', 'Read-Metadata.py')) {
            [IO.File]::Copy((Join-Path $PSScriptRoot "../$Name"), (Join-Path $Destination "scripts/$Name"))
        }
        foreach ($Name in @('skill-metadata.schema.json', 'repository-defaults.schema.json')) {
            [IO.File]::Copy((Join-Path $PSScriptRoot "../../$Name"), (Join-Path $Destination $Name))
        }
        Save-VersionFixture -Tags example/1.0.0,preparer/1.0.0
        Add-VersionFixtureChange -Id preparer
        $Helper = Join-Path $Destination 'scripts/Invoke-VersionPreparation.ps1'
        $Decisions = ConvertTo-Json @{ preparer = 'patch' } -Compress
        $Output = & pwsh -NoProfile -File $Helper -RepoRoot $script:Root -PythonPath $script:Python -ImpactJson $Decisions 2>&1
        $LASTEXITCODE | Should -Be 0
        $Plan = ($Output -join "`n") | ConvertFrom-Json
        $Output = & pwsh -NoProfile -File $Helper -RepoRoot $script:Root -PythonPath $script:Python -ImpactJson $Decisions -Apply -ReviewedFingerprint $Plan.Fingerprint 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($Output -join '')
        (Get-VersionFixtureMetadata -Id preparer).version | Should -Be '1.0.1'
        $Output = & pwsh -NoProfile -File $Helper -RepoRoot $script:Root -PythonPath $script:Python -ImpactJson $Decisions 2>&1
        $LASTEXITCODE | Should -Be 0
        (($Output -join "`n") | ConvertFrom-Json).Changes.Count | Should -Be 0
    }

    It 'reports nonzero CLI exit for an unreviewed apply and failed subprocess' {
        $Output = & pwsh -NoProfile -File $script:PreparationScript -RepoRoot $script:Root -PythonPath $script:Python -Apply 2>&1
        $LASTEXITCODE | Should -Be 1
        ($Output -join '') | Should -Match 'incomplete'
        $Output = & pwsh -NoProfile -File $script:PreparationScript -RepoRoot $script:Root -PythonPath (Get-Command git -CommandType Application -TotalCount 1).Source 2>&1
        $LASTEXITCODE | Should -Be 1
        ($Output -join '') | Should -Match 'failed'
    }
}
