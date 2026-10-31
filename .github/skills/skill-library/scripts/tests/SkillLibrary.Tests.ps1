#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../SkillLibrary.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'SkillLibraryFixture.psm1') -Force
    function Get-Errors { Test-SkillComponent -RepoRoot $Repo -Component (Get-SkillComponent -RepoRoot $Repo) }
    function Get-VersionErrors { Test-SkillVersion -RepoRoot $Repo -Component (Get-SkillComponent -RepoRoot $Repo) }
    function Get-Alpha { Get-SkillComponent -RepoRoot $Repo | Where-Object Id -eq 'alpha' }
}

Describe 'Sidecar validation' -Tag 'Unit' {
    BeforeEach { $Repo = New-SkillFixture $TestDrive }

    It 'accepts a consistent set of skills' {
        @(Get-Errors) | Should -BeNullOrEmpty
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'an unknown required skill'; Metadata = "version: 1.0.0`nrequired:`n  - id: missing`n    version: 1.0.0`n"; Expected = '*unknown skill*' }
        @{ Case = 'a required cycle'; Metadata = "version: 1.0.0`nrequired:`n  - id: alpha`n    version: 1.0.0`n"; Expected = '*cycle*' }
        @{ Case = 'a malformed version'; Metadata = "version: '1.0'`n"; Expected = '*schema*' }
        @{ Case = 'an unknown field'; Metadata = "version: 1.0.0`ntooling: []`n"; Expected = '*schema*' }
        @{ Case = 'a missing external file'; Metadata = "version: 1.0.0`nexternalFiles: [docs/missing.md]`n"; Expected = '*does not exist*' }
        @{ Case = 'a self reference'; Metadata = "version: 1.0.0`nrelated:`n  - id: beta`n    reason: Self.`n"; Expected = '*references itself*' }
    ) {
        Write-FixtureText $Repo '.github/skills/beta/skill.metadata.yaml' $Metadata
        @(Get-Errors) -join "`n" | Should -BeLike $Expected
    }

    It 'reports a skill without a sidecar' {
        Write-FixtureSkill $Repo 'delta'
        @(Get-Errors) -join "`n" | Should -BeLike '*delta: missing skill.metadata.yaml*'
    }

    It 'skips Git-ignored private skills' {
        Write-FixtureText $Repo '.gitignore' "/.github/skills/private/`n"
        Write-FixtureSkill $Repo 'private' "version: oops`n"
        (Get-SkillComponent -RepoRoot $Repo).Id | Should -Not -Contain 'private'
        Get-SkillWithoutMetadata -RepoRoot $Repo | Should -BeNullOrEmpty
    }
}

Describe 'Extension archives' -Tag 'Unit' {
    BeforeEach { $Repo = New-SkillFixture $TestDrive }

    It 'packages the skill, its external files and LICENSE with a Spec Kit manifest' {
        $Archive = New-SkillExtensionArchive -RepoRoot $Repo -Component (Get-Alpha) -OutputDirectory (Join-Path $TestDrive 'out')
        $Zip = [IO.Compression.ZipFile]::OpenRead($Archive.Path)
        try {
            $Zip.Entries.FullName | Should -Be @('extension.yml', 'resources/.github/instructions/x.instructions.md',
                'resources/.github/skills/alpha/SKILL.md', 'resources/.github/skills/alpha/skill.metadata.yaml', 'resources/LICENSE')
            $Reader = [IO.StreamReader]::new($Zip.GetEntry('extension.yml').Open())
            $Manifest = ConvertFrom-SkillYaml $Reader.ReadToEnd()
            $Reader.Dispose()
        }
        finally { $Zip.Dispose() }
        $Manifest.extension.id | Should -Be 'alpha'
        $Manifest.extension.version | Should -Be '1.0.0'
        $Manifest.provides.templates[0].file | Should -Be 'resources/.github/skills/alpha/SKILL.md'
    }

    It 'produces identical bytes on rebuild' {
        $First = New-SkillExtensionArchive -RepoRoot $Repo -Component (Get-Alpha) -OutputDirectory (Join-Path $TestDrive 'a')
        $Second = New-SkillExtensionArchive -RepoRoot $Repo -Component (Get-Alpha) -OutputDirectory (Join-Path $TestDrive 'b')
        $Second.Sha256 | Should -Be $First.Sha256
    }

    It 'refuses uncommitted changes' {
        Write-FixtureText $Repo '.github/skills/alpha/SKILL.md' "changed`n"
        { New-SkillExtensionArchive -RepoRoot $Repo -Component (Get-Alpha) -OutputDirectory (Join-Path $TestDrive 'c') } | Should -Throw '*commit or stash*'
    }
}

Describe 'Version checks' -Tag 'Unit' {
    BeforeEach {
        $Repo = New-SkillFixture $TestDrive
        foreach ($Id in 'alpha', 'beta', 'gamma') { Invoke-FixtureGit $Repo tag "$Id/1.0.0" }
    }

    It 'accepts unchanged released skills' {
        @(Get-VersionErrors) | Should -BeNullOrEmpty
    }

    It 'reads the highest released tag' {
        Invoke-FixtureGit $Repo tag 'beta/1.10.0'
        Invoke-FixtureGit $Repo tag 'beta/1.9.0'
        Get-SkillReleasedVersion -RepoRoot $Repo -Id 'beta' | Should -Be ([version]'1.10.0')
    }

    It 'rejects a change to a skill or its external file without a bump' {
        Write-FixtureText $Repo '.github/instructions/x.instructions.md' "# Changed`n"
        @(Get-VersionErrors) -join "`n" | Should -BeLike '*alpha: changed since alpha/1.0.0*'
    }

    It 'rejects a stale required pin' {
        Write-FixtureText $Repo '.github/skills/beta/skill.metadata.yaml' "version: 1.0.1`n"
        @(Get-VersionErrors) -join "`n" | Should -BeLike '*alpha: requires beta 1.0.0 but its version is 1.0.1*'
    }

    It 'accepts a single <Level> bump from the released tag' -ForEach @(
        @{ Level = 'patch'; Version = '1.0.1' }
        @{ Level = 'minor'; Version = '1.1.0' }
        @{ Level = 'major'; Version = '2.0.0' }
    ) {
        Write-FixtureText $Repo '.github/skills/gamma/skill.metadata.yaml' "version: $Version`n"
        @(Get-VersionErrors) | Should -BeNullOrEmpty
    }

    It 'rejects a version that skips past one bump' {
        Write-FixtureText $Repo '.github/skills/gamma/skill.metadata.yaml' "version: 1.0.2`n"
        @(Get-VersionErrors) -join "`n" | Should -BeLike '*gamma: version 1.0.2 skips past one bump from released 1.0.0*'
    }

    It 'rejects a version below the released tag' {
        Write-FixtureText $Repo '.github/skills/gamma/skill.metadata.yaml' "version: 0.9.0`n"
        @(Get-VersionErrors) -join "`n" | Should -BeLike '*gamma: version 0.9.0 is lower than released 1.0.0*'
    }
}

Describe 'Catalog' -Tag 'Unit' {
    It 'advertises the highest version and keeps history under releases' {
        $Release = @(
            [pscustomobject]@{ Id = 'alpha'; Version = '1.0.0'; Url = 'https://example.com/a1.zip'; Sha256 = ('a' * 64); Description = 'Old.'; Facets = @('x'); Required = @(@{ id = 'beta'; version = '1.0.0' }); Related = @() }
            [pscustomobject]@{ Id = 'alpha'; Version = '1.1.0'; Url = 'https://example.com/a2.zip'; Sha256 = ('b' * 64); Description = 'New.'; Facets = @('x'); Required = @(@{ id = 'beta'; version = '1.0.0' }); Related = @() }
            [pscustomobject]@{ Id = 'beta'; Version = '1.0.0'; Url = 'https://example.com/b.zip'; Sha256 = ('c' * 64); Description = 'Beta.'; Facets = @(); Required = @(); Related = @() }
        )
        $Catalog = New-SkillCatalog -Release $Release
        $Catalog.extensions['alpha'].version | Should -Be '1.1.0'
        $Catalog.extensions['alpha'].description | Should -Be 'New.'
        $Catalog.extensions['alpha'].releases['1.0.0'].sha256 | Should -Be ('a' * 64)
        $Catalog.extensions['alpha'].skill_library.required[0].id | Should -Be 'beta'
        $Catalog.extensions['beta'].Contains('releases') | Should -BeFalse
    }

    It 'renders an HTML page with encoded catalog text' {
        $Release = @([pscustomobject]@{ Id = 'alpha'; Version = '1.0.0'; Url = 'https://example.com/a.zip'; Sha256 = ('a' * 64)
                Description = 'Uses <script> & more.'; Facets = @(); Required = @(); Related = @() })
        $Page = New-SkillCatalogPage -Catalog (New-SkillCatalog -Release $Release)
        $Page | Should -BeLike '*Uses &lt;script&gt; &amp; more.*'
        $Page | Should -Not -BeLike '*<script>*'
    }
}
