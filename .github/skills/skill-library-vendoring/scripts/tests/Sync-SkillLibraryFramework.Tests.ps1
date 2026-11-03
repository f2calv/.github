#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../../skill-library/scripts/tests/SkillLibraryFixture.psm1') -Force
    $Script = Join-Path $PSScriptRoot '../Sync-SkillLibraryFramework.ps1'
    $Manifest = @'
managed:
  - path: .github/skills/skill-library/
    exclude:
      - .github/skills/skill-library/skill.metadata.yaml
  - path: src/skill-library-extension/
seeded:
  - path: .github/skill-library.config.yaml
    from: .github/skills/skill-library-vendoring/assets/skill-library.config.yaml
  - path: pyproject.toml
    from: pyproject.toml
'@

    # Source with skill-library/1.0.0 and 1.1.0: 1.1.0 changes SKILL.md, adds new.ps1, retires old.md and changes the config template.
    function New-SourceFixture {
        $Repo = Join-Path $TestDrive "source-$([guid]::NewGuid())"
        [void][IO.Directory]::CreateDirectory($Repo)
        Invoke-FixtureGit $Repo init -q -b main
        Write-FixtureText $Repo '.github/skills/skill-library-vendoring/framework.yaml' $Manifest
        Write-FixtureText $Repo '.github/skills/skill-library-vendoring/assets/skill-library.config.yaml' "catalogUrl: https://example.com/catalog.json`n"
        Write-FixtureText $Repo '.github/skills/skill-library/SKILL.md' "# Library 1.0`n"
        Write-FixtureText $Repo '.github/skills/skill-library/skill.metadata.yaml' "version: 9.9.9`n"
        Write-FixtureText $Repo '.github/skills/skill-library/scripts/A.ps1' "'a'`n"
        Write-FixtureText $Repo '.github/skills/other/SKILL.md' "# Not framework`n"
        Write-FixtureText $Repo 'src/skill-library-extension/extension.yml' "id: skill`n"
        Write-FixtureText $Repo 'src/skill-library-extension/old.md' "# Old`n"
        Write-FixtureText $Repo 'pyproject.toml' "[project]`nname = `"tooling`"`n"
        Invoke-FixtureGit $Repo add -A
        Invoke-FixtureGit $Repo commit -q -m one
        Invoke-FixtureGit $Repo tag skill-library/1.0.0
        Write-FixtureText $Repo '.github/skills/skill-library/SKILL.md' "# Library 1.1`n"
        Write-FixtureText $Repo '.github/skills/skill-library/scripts/A.ps1' "'a2'`n"
        Write-FixtureText $Repo '.github/skills/skill-library/scripts/new.ps1' "'new'`n"
        Remove-Item -LiteralPath (Join-Path $Repo 'src/skill-library-extension/old.md')
        Write-FixtureText $Repo '.github/skills/skill-library-vendoring/assets/skill-library.config.yaml' "catalogUrl: https://example.com/v2.json`n"
        Invoke-FixtureGit $Repo add -A
        Invoke-FixtureGit $Repo commit -q -m two
        Invoke-FixtureGit $Repo tag skill-library/1.1.0
        Invoke-FixtureGit $Repo remote add origin 'https://user:secret-token@git.test/owner/framework.git'
        return $Repo
    }

    function New-TargetFixture {
        $Repo = Join-Path $TestDrive "target-$([guid]::NewGuid())"
        [void][IO.Directory]::CreateDirectory($Repo)
        Invoke-FixtureGit $Repo init -q -b main
        Write-FixtureText $Repo 'pyproject.toml' "[project]`nname = `"theirs`"`n"
        return $Repo
    }

    function Invoke-Sync([string]$Ref = '', [switch]$WhatIf) {
        $Parameters = @{ Source = $Source; Target = $Target }
        if ($Ref) { $Parameters.Ref = $Ref }
        @(& $Script @Parameters -WhatIf:$WhatIf)
    }
    function Get-Action($Results, [string]$Path) { $Results | Where-Object Path -CEQ $Path | Select-Object -First 1 | ForEach-Object Action }
    function Get-Lock { Get-Content -Raw (Join-Path $Target '.github/skill-library.framework.lock.json') | ConvertFrom-Json -AsHashtable }
    function Read-Target([string]$Path) { [IO.File]::ReadAllText((Join-Path $Target $Path)) }
}

Describe 'Sync-SkillLibraryFramework' -Tag 'Unit' {
    BeforeEach {
        $Source = New-SourceFixture
        $Target = New-TargetFixture
    }

    It 'changes nothing with -WhatIf' {
        $Before = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'skill-library-sync-*').Count
        $Results = Invoke-Sync -Ref 'skill-library/1.0.0' -WhatIf
        Get-Action $Results '.github/skills/skill-library/SKILL.md' | Should -Be 'Added'
        Join-Path $Target '.github/skills/skill-library' | Should -Not -Exist
        Join-Path $Target '.github/skill-library.framework.lock.json' | Should -Not -Exist
        @(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'skill-library-sync-*').Count | Should -Be $Before
    }

    It 'adds managed files, seeds missing ones once and records the source in the lock' {
        $Results = Invoke-Sync -Ref 'skill-library/1.0.0'
        foreach ($Path in '.github/skills/skill-library/SKILL.md', '.github/skills/skill-library/scripts/A.ps1', 'src/skill-library-extension/extension.yml', 'src/skill-library-extension/old.md') {
            Get-Action $Results $Path | Should -Be 'Added'
        }
        Get-Action $Results '.github/skill-library.config.yaml' | Should -Be 'Seeded'
        Get-Action $Results 'pyproject.toml' | Should -Be 'Skipped'
        Join-Path $Target '.github/skills/skill-library/skill.metadata.yaml' | Should -Not -Exist
        Join-Path $Target '.github/skills/other' | Should -Not -Exist
        Read-Target 'pyproject.toml' | Should -BeLike '*theirs*'
        $Lock = Get-Lock
        $Lock.source.ref | Should -Be 'skill-library/1.0.0'
        $Lock.source.commit | Should -Be (git -C $Source rev-parse 'skill-library/1.0.0^{commit}')
        $Lock.source.repository | Should -Be 'https://git.test/owner/framework.git'
        $Lock.files['.github/skills/skill-library/SKILL.md'].kind | Should -Be 'managed'
        $Lock.files['.github/skills/skill-library/SKILL.md'].sha256 | Should -Be (Get-FileHash (Join-Path $Target '.github/skills/skill-library/SKILL.md')).Hash.ToLowerInvariant()
        $Lock.files['.github/skill-library.config.yaml'].kind | Should -Be 'seeded'
        $Lock.files.ContainsKey('pyproject.toml') | Should -BeFalse
    }

    It 'updates unedited files, keeps edited ones, removes retired ones and never reseeds' {
        Invoke-Sync -Ref 'skill-library/1.0.0' | Out-Null
        Write-FixtureText $Target '.github/skills/skill-library/scripts/A.ps1' "'local edit'`n"
        $EditedHash = (Get-Lock).files['.github/skills/skill-library/scripts/A.ps1'].sha256
        Write-FixtureText $Target '.github/skill-library.config.yaml' "catalogUrl: https://catalog.test/catalog.json`n"
        $Results = Invoke-Sync -Ref 'skill-library/1.1.0'
        Get-Action $Results '.github/skills/skill-library/SKILL.md' | Should -Be 'Updated'
        Get-Action $Results '.github/skills/skill-library/scripts/A.ps1' | Should -Be 'Kept'
        Get-Action $Results '.github/skills/skill-library/scripts/new.ps1' | Should -Be 'Added'
        Get-Action $Results 'src/skill-library-extension/extension.yml' | Should -Be 'Unchanged'
        Get-Action $Results 'src/skill-library-extension/old.md' | Should -Be 'Removed'
        Get-Action $Results '.github/skill-library.config.yaml' | Should -BeNullOrEmpty
        Read-Target '.github/skills/skill-library/SKILL.md' | Should -Be "# Library 1.1`n"
        Read-Target '.github/skills/skill-library/scripts/A.ps1' | Should -Be "'local edit'`n"
        Read-Target '.github/skill-library.config.yaml' | Should -Be "catalogUrl: https://catalog.test/catalog.json`n"
        Join-Path $Target 'src/skill-library-extension/old.md' | Should -Not -Exist
        $Lock = Get-Lock
        $Lock.source.ref | Should -Be 'skill-library/1.1.0'
        $Lock.files['.github/skills/skill-library/scripts/A.ps1'].sha256 | Should -Be $EditedHash
        $Lock.files.ContainsKey('src/skill-library-extension/old.md') | Should -BeFalse
    }

    It 'keeps a file the target already had before the first sync' {
        Write-FixtureText $Target 'src/skill-library-extension/extension.yml' "id: mine`n"
        $Results = Invoke-Sync -Ref 'skill-library/1.0.0'
        Get-Action $Results 'src/skill-library-extension/extension.yml' | Should -Be 'Kept'
        Read-Target 'src/skill-library-extension/extension.yml' | Should -Be "id: mine`n"
        (Get-Lock).files.ContainsKey('src/skill-library-extension/extension.yml') | Should -BeFalse
    }

    It 'keeps a retired file that was edited' {
        Invoke-Sync -Ref 'skill-library/1.0.0' | Out-Null
        Write-FixtureText $Target 'src/skill-library-extension/old.md' "# Edited`n"
        Get-Action (Invoke-Sync -Ref 'skill-library/1.1.0') 'src/skill-library-extension/old.md' | Should -Be 'Kept'
        Read-Target 'src/skill-library-extension/old.md' | Should -Be "# Edited`n"
    }

    It 'defaults to the highest skill-library tag by version' {
        Invoke-FixtureGit $Source tag skill-library/1.9.0 'skill-library/1.0.0'
        Invoke-FixtureGit $Source tag skill-library/1.10.0 'skill-library/1.1.0'
        Invoke-Sync | Out-Null
        (Get-Lock).source.ref | Should -Be 'skill-library/1.10.0'
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'a tag without a framework manifest'; Setup = { Invoke-FixtureGit $Source rm -q -r .github/skills/skill-library-vendoring; Invoke-FixtureGit $Source commit -q -m drop; Invoke-FixtureGit $Source tag skill-library/1.2.0 }; Ref = 'skill-library/1.2.0'; Expected = '*has no .github/skills/skill-library-vendoring/framework.yaml*' }
        @{ Case = 'an unknown tag'; Setup = {}; Ref = 'skill-library/7.0.0'; Expected = "*has no tag 'skill-library/7.0.0'*" }
        @{ Case = 'a tag of another component'; Setup = {}; Ref = 'docs-adr/1.0.0'; Expected = '*must be a skill-library/<version> tag*' }
    ) {
        & $Setup
        { Invoke-Sync -Ref $Ref } | Should -Throw $Expected
    }

    It 'refuses to sync a repository into itself' {
        { & $Script -Source $Source -Target $Source } | Should -Throw '*must be different repositories*'
    }
}
