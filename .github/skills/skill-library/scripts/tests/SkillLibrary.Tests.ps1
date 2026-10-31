#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../SkillLibrary.psm1') -Force
    $script:Scripts = Join-Path $PSScriptRoot '..'
    $script:Consumer = Join-Path $PSScriptRoot '../../../../../src/skill-library-extension/scripts/Invoke-SkillLibrary.ps1'
    $env:GIT_AUTHOR_NAME = $env:GIT_COMMITTER_NAME = 'Test'
    $env:GIT_AUTHOR_EMAIL = $env:GIT_COMMITTER_EMAIL = 'test@example.com'

    function Git { Invoke-SkillTool git ([string[]]$args) -WorkingDirectory $script:Repo | Out-Null }

    function Write-Text([string]$Path, [string]$Text) {
        $Full = Join-Path $script:Repo $Path
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Full))
        [IO.File]::WriteAllText($Full, $Text)
    }

    function Write-Skill([string]$Id, [string]$Metadata) {
        Write-Text ".github/skills/$Id/SKILL.md" "---`nname: $Id`ndescription: Guidance for $Id.`n---`n`n# $Id`n"
        Write-Text ".github/skills/$Id/skill.metadata.yaml" $Metadata
    }

    function New-Fixture {
        $script:Repo = Join-Path $TestDrive ([guid]::NewGuid())
        [void][IO.Directory]::CreateDirectory($script:Repo)
        Git init -q -b main
        Write-Text 'LICENSE' "MIT`n"
        Write-Text '.github/instructions/x.instructions.md' "# X`n"
        Write-Skill 'alpha' "version: 1.0.0`nfacets: [architecture]`nrequired:`n  - id: beta`n    version: 1.0.0`nrelated:`n  - id: gamma`n    reason: Optional extra.`nexternalFiles:`n  - .github/instructions/x.instructions.md`n"
        Write-Skill 'beta' "version: 1.0.0`n"
        Write-Skill 'gamma' "version: 1.0.0`n"
        Git add -A
        Git commit -q -m init
    }

    function Get-Errors { Test-SkillComponent -RepoRoot $script:Repo -Component (Get-SkillComponent -RepoRoot $script:Repo) }
    function Get-VersionErrors { Test-SkillVersion -RepoRoot $script:Repo -Component (Get-SkillComponent -RepoRoot $script:Repo) }
    function Get-Version([string]$Id) { (Read-SkillYaml (Join-Path $script:Repo ".github/skills/$Id/skill.metadata.yaml")).version }
}

Describe 'Sidecar validation' -Tag 'Unit' {
    BeforeEach { New-Fixture }

    It 'accepts a consistent set of skills' {
        @(Get-Errors) | Should -BeNullOrEmpty
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'an unknown required skill'; Id = 'beta'; Metadata = "version: 1.0.0`nrequired:`n  - id: missing`n    version: 1.0.0`n"; Expected = '*unknown skill*' }
        @{ Case = 'a required cycle'; Id = 'beta'; Metadata = "version: 1.0.0`nrequired:`n  - id: alpha`n    version: 1.0.0`n"; Expected = '*cycle*' }
        @{ Case = 'a malformed version'; Id = 'beta'; Metadata = "version: '1.0'`n"; Expected = '*schema*' }
        @{ Case = 'an unknown field'; Id = 'beta'; Metadata = "version: 1.0.0`ntooling: []`n"; Expected = '*schema*' }
        @{ Case = 'a missing external file'; Id = 'beta'; Metadata = "version: 1.0.0`nexternalFiles: [docs/missing.md]`n"; Expected = '*does not exist*' }
    ) {
        Write-Text ".github/skills/$Id/skill.metadata.yaml" $Metadata
        @(Get-Errors) -join "`n" | Should -BeLike $Expected
    }

    It 'skips Git-ignored private skills' {
        Write-Text '.gitignore' "/.github/skills/private/`n"
        Write-Skill 'private' "version: oops`n"
        (Get-SkillComponent -RepoRoot $script:Repo).Id | Should -Not -Contain 'private'
    }
}

Describe 'Extension archives' -Tag 'Unit' {
    BeforeEach { New-Fixture }

    It 'packages the skill, its external files and LICENSE with a Spec Kit manifest' {
        $Component = Get-SkillComponent -RepoRoot $script:Repo | Where-Object Id -eq 'alpha'
        $Archive = New-SkillExtensionArchive -RepoRoot $script:Repo -Component $Component -OutputDirectory (Join-Path $TestDrive 'out1')
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
        $Component = Get-SkillComponent -RepoRoot $script:Repo | Where-Object Id -eq 'alpha'
        $First = New-SkillExtensionArchive -RepoRoot $script:Repo -Component $Component -OutputDirectory (Join-Path $TestDrive 'a')
        $Second = New-SkillExtensionArchive -RepoRoot $script:Repo -Component $Component -OutputDirectory (Join-Path $TestDrive 'b')
        $Second.Sha256 | Should -Be $First.Sha256
    }

    It 'refuses uncommitted changes' {
        Write-Text '.github/skills/alpha/SKILL.md' "changed`n"
        $Component = Get-SkillComponent -RepoRoot $script:Repo | Where-Object Id -eq 'alpha'
        { New-SkillExtensionArchive -RepoRoot $script:Repo -Component $Component -OutputDirectory (Join-Path $TestDrive 'c') } | Should -Throw '*commit or stash*'
    }
}

Describe 'Version checks and bumps' -Tag 'Unit' {
    BeforeEach {
        New-Fixture
        foreach ($Id in 'alpha', 'beta', 'gamma') { Git tag "$Id/1.0.0" }
    }

    It 'accepts unreleased and unchanged released skills' {
        @(Get-VersionErrors) | Should -BeNullOrEmpty
    }

    It 'rejects a change to a skill or its external file without a bump' {
        Write-Text '.github/instructions/x.instructions.md' "# Changed`n"
        @(Get-VersionErrors) -join "`n" | Should -BeLike '*alpha: changed since alpha/1.0.0*'
    }

    It 'rejects a stale required pin' {
        Write-Text '.github/skills/beta/skill.metadata.yaml' "version: 1.0.1`n"
        @(Get-VersionErrors) -join "`n" | Should -BeLike '*alpha: requires beta 1.0.0 but its version is 1.0.1*'
    }

    It 'bumps a changed skill once and cascades the pin and a patch bump to dependents' {
        Write-Text '.github/skills/beta/SKILL.md' "---`nname: beta`ndescription: Changed.`n---`n"
        & (Join-Path $script:Scripts 'Set-SkillVersion.ps1') -RepoRoot $script:Repo -Bump minor 6> $null
        & (Join-Path $script:Scripts 'Set-SkillVersion.ps1') -RepoRoot $script:Repo -Id beta -Bump minor 6> $null
        Get-Version 'beta' | Should -Be '1.1.0'
        Get-Version 'alpha' | Should -Be '1.0.1'
        Get-Version 'gamma' | Should -Be '1.0.0'
        (Read-SkillYaml (Join-Path $script:Repo '.github/skills/alpha/skill.metadata.yaml')).required[0].version | Should -Be '1.1.0'
        @(Get-VersionErrors) | Should -BeNullOrEmpty
    }

    It 'preserves comments when bumping' {
        Write-Text '.github/skills/gamma/skill.metadata.yaml' "# keep me`nversion: 1.0.0`n"
        & (Join-Path $script:Scripts 'Set-SkillVersion.ps1') -RepoRoot $script:Repo -Id gamma 6> $null
        Get-Content -Raw (Join-Path $script:Repo '.github/skills/gamma/skill.metadata.yaml') | Should -Be "# keep me`nversion: 1.0.1`n"
    }
}

Describe 'Catalog and consumer plan' -Tag 'Unit' {
    BeforeAll {
        $script:CatalogPath = Join-Path $TestDrive 'catalog.json'
        $Release = @(
            [pscustomobject]@{ Id = 'alpha'; Version = '1.0.0'; Url = 'https://example.com/alpha-1.0.0.zip'; Sha256 = ('a' * 64); Description = 'Old.'; Facets = @('architecture')
                Required = @(@{ id = 'beta'; version = '1.0.0' }); Related = @(@{ id = 'gamma'; reason = 'Optional extra.' }) }
            [pscustomobject]@{ Id = 'alpha'; Version = '1.1.0'; Url = 'https://example.com/alpha-1.1.0.zip'; Sha256 = ('b' * 64); Description = 'Alpha.'; Facets = @('architecture')
                Required = @(@{ id = 'beta'; version = '1.0.0' }); Related = @(@{ id = 'gamma'; reason = 'Optional extra.' }) }
            [pscustomobject]@{ Id = 'beta'; Version = '1.0.0'; Url = 'https://example.com/beta-1.0.0.zip'; Sha256 = ('c' * 64); Description = 'Beta.'; Facets = @(); Required = @(); Related = @() }
            [pscustomobject]@{ Id = 'gamma'; Version = '1.0.0'; Url = 'https://example.com/gamma-1.0.0.zip'; Sha256 = ('d' * 64); Description = 'Gamma.'; Facets = @(); Required = @(); Related = @() }
        )
        $script:Catalog = New-SkillCatalog -Release $Release
        [IO.File]::WriteAllText($script:CatalogPath, ($script:Catalog | ConvertTo-Json -Depth 20))
        $script:Workspace = Join-Path $TestDrive 'consumer'
        [void][IO.Directory]::CreateDirectory("$script:Workspace/.specify/extensions")
    }

    It 'advertises the highest version and keeps history under releases' {
        $Alpha = $script:Catalog.extensions['alpha']
        $Alpha.version | Should -Be '1.1.0'
        $Alpha.download_url | Should -Be 'https://example.com/alpha-1.1.0.zip'
        $Alpha.releases['1.0.0'].sha256 | Should -Be ('a' * 64)
        $Alpha.skill_library.required[0].id | Should -Be 'beta'
    }

    It 'plans required skills first and offers related skills' {
        $Output = & $script:Consumer plan alpha -CatalogUrl $script:CatalogPath -Workspace $script:Workspace | Out-String
        $Output | Should -Match '(?s)beta\s+1\.0\.0\s+install\s+required by alpha.*alpha\s+1\.1\.0\s+install\s+requested'
        $Output | Should -Match 'gamma\s+not installed\s+alpha\s+Optional extra\.'
    }

    It 'installs a selected related skill and reports version conflicts' {
        [IO.File]::WriteAllText("$script:Workspace/.specify/extensions/.registry", '{"schema_version":"1.0","extensions":{"beta":{"version":"0.9.0","enabled":true}}}')
        $Output = & $script:Consumer plan alpha -Version 1.0.0 -Related gamma -CatalogUrl $script:CatalogPath -Workspace $script:Workspace | Out-String
        $Output | Should -Match 'beta\s+1\.0\.0\s+conflict: 0\.9\.0 installed'
        $Output | Should -Match 'alpha\s+1\.0\.0\s+install'
        $Output | Should -Match 'gamma\s+1\.0\.0\s+install\s+related, selected'
    }

    It 'reports an unknown skill' {
        { & $script:Consumer plan missing -CatalogUrl $script:CatalogPath -Workspace $script:Workspace } | Should -Throw "*can't find the skill 'missing'*"
    }
}
