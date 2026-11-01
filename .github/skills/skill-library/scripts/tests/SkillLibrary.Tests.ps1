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
    BeforeEach { $Repo = New-SkillFixture (Join-Path $TestDrive "workspace $([char]0x00E9)") }

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
        @{ Case = 'a non-boolean agentPlugin'; Metadata = "version: 1.0.0`nagentPlugin: maybe`n"; Expected = '*schema*' }
    ) {
        Write-FixtureText $Repo '.github/skills/beta/skill.metadata.yaml' $Metadata
        @(Get-Errors) -join "`n" | Should -BeLike $Expected
    }

    It 'reports a skill without a sidecar' {
        Write-FixtureSkill $Repo 'delta'
        @(Get-Errors) -join "`n" | Should -BeLike '*delta: missing skill.metadata.yaml*'
    }

    It 'skips Git-ignored private skills <Case>' -ForEach @(
        @{ Case = 'with a sidecar via .gitignore'; IgnoreFile = '.gitignore'; Metadata = "version: oops`n" }
        @{ Case = 'without a sidecar via .gitignore'; IgnoreFile = '.gitignore'; Metadata = '' }
        @{ Case = 'with a sidecar via info/exclude'; IgnoreFile = '.git/info/exclude'; Metadata = "version: oops`n" }
        @{ Case = 'without a sidecar via info/exclude'; IgnoreFile = '.git/info/exclude'; Metadata = '' }
    ) {
        Invoke-FixtureGit $Repo config core.quotePath true
        Write-FixtureText $Repo $IgnoreFile "/.github/skills/private/`n"
        Write-FixtureSkill $Repo 'private' $Metadata
        (Get-SkillComponent -RepoRoot $Repo).Id | Should -Not -Contain 'private'
        Get-SkillWithoutMetadata -RepoRoot $Repo | Should -BeNullOrEmpty
        @(Get-Errors) | Should -BeNullOrEmpty
    }

    It 'fails <Discovery> when Git ignore status cannot be determined' -ForEach @(
        @{ Discovery = 'Get-SkillComponent' }
        @{ Discovery = 'Get-SkillWithoutMetadata' }
    ) {
        Write-FixtureSkill $Repo 'delta'
        Rename-Item -LiteralPath (Join-Path $Repo '.git') -NewName '.git-disabled'
        { & $Discovery -RepoRoot $Repo } | Should -Throw '*Cannot determine Git ignore status*'
    }

    It 'reports a SKILL.md name that does not match its folder' {
        Write-FixtureText $Repo '.github/skills/beta/SKILL.md' "---`nname: other`ndescription: Beta.`n---`n"
        @(Get-Errors) -join "`n" | Should -BeLike "*beta: SKILL.md name 'other' must match the folder name.*"
    }

    It 'reports a SKILL.md description over the Agent Skills limit' {
        Write-FixtureText $Repo '.github/skills/beta/SKILL.md' "---`nname: beta`ndescription: $('x' * 1025)`n---`n"
        @(Get-Errors) -join "`n" | Should -BeLike '*beta: SKILL.md description must be 1-1024 characters.*'
    }

    It 'packages skills as Agent Plugins unless the sidecar opts out' {
        Write-FixtureText $Repo '.github/skills/gamma/skill.metadata.yaml' "version: 1.0.0`nagentPlugin: false`n"
        $Components = Get-SkillComponent -RepoRoot $Repo
        ($Components | Where-Object Id -eq 'alpha').AgentPlugin | Should -BeTrue
        ($Components | Where-Object Id -eq 'gamma').AgentPlugin | Should -BeFalse
        @(Get-Errors) | Should -BeNullOrEmpty
    }
}

Describe 'Portable frontmatter' -Tag 'Unit' {
    It 'moves client-specific fields into string metadata and keeps the body' {
        $Markdown = "---`nname: alpha`ndescription: 'Does things: well.'`nargument-hint: '[task]'`nuser-invocable: true`nmetadata:`n  owner: example`n---`n`n# Body`n"
        $Portable = ConvertTo-SkillPortableMarkdown $Markdown
        $Front = Get-SkillFrontmatter $Portable
        @($Front.Keys) | Should -Be @('name', 'description', 'metadata')
        $Front.description | Should -Be 'Does things: well.'
        $Front.metadata['owner'] | Should -Be 'example'
        $Front.metadata['argument-hint'] | Should -Be '[task]'
        $Front.metadata['user-invocable'] | Should -BeOfType [string]
        $Front.metadata['user-invocable'] | Should -Be 'true'
        $Portable | Should -BeLike "*---`n`n# Body`n"
        Test-SkillPortableFrontmatter -Id 'alpha' -Markdown $Markdown | Should -BeNullOrEmpty
    }

    It 'returns already portable Markdown unchanged' {
        $Markdown = "---`nname: alpha`ndescription: Fine.`n---`nBody`n"
        ConvertTo-SkillPortableMarkdown $Markdown | Should -BeExactly $Markdown
    }

    It 'returns Markdown without frontmatter unchanged' {
        ConvertTo-SkillPortableMarkdown "# No frontmatter`n" | Should -BeExactly "# No frontmatter`n"
    }

    It 'is idempotent' {
        $Once = ConvertTo-SkillPortableMarkdown "---`nname: alpha`ndescription: Fine.`nargument-hint: x`n---`nBody`n"
        ConvertTo-SkillPortableMarkdown $Once | Should -BeExactly $Once
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'a description over 1024 characters'; Front = "name: alpha`ndescription: $('x' * 1025)"; Expected = '*description must be 1-1024*' }
        @{ Case = 'non-string metadata'; Front = "name: alpha`ndescription: Fine.`nmetadata:`n  count: 3"; Expected = '*metadata values must be strings*' }
        @{ Case = 'a long compatibility'; Front = "name: alpha`ndescription: Fine.`ncompatibility: $('x' * 501)"; Expected = '*compatibility exceeds 500*' }
        @{ Case = 'non-map metadata'; Front = "name: alpha`ndescription: Fine.`nmetadata: flat"; Expected = '*metadata must be a map*' }
        @{ Case = 'a missing description'; Front = 'name: alpha'; Expected = '*description must be 1-1024*' }
        @{ Case = 'a mismatched name'; Front = "name: beta`ndescription: Fine."; Expected = "*name 'beta' must match*" }
    ) {
        @(Test-SkillPortableFrontmatter -Id 'alpha' -Markdown "---`n$Front`n---`n") -join "`n" | Should -BeLike $Expected
    }
}

Describe 'Agent Plugin archives' -Tag 'Unit' {
    BeforeEach {
        $Repo = New-SkillFixture $TestDrive
        Write-FixtureText $Repo '.github/skills/alpha/SKILL.md' "---`nname: alpha`ndescription: Guidance for alpha.`nuser-invocable: true`n---`n`nSee [X](../../instructions/x.instructions.md).`n"
        Invoke-FixtureGit $Repo commit -q -am hint
        function Read-Entry([IO.Compression.ZipArchive]$Zip, [string]$Name) {
            $Reader = [IO.StreamReader]::new($Zip.GetEntry($Name).Open())
            try { $Reader.ReadToEnd() } finally { $Reader.Dispose() }
        }
    }

    It 'lays out plugin.json, the skill and its external files so relative links resolve' {
        $Archive = New-SkillPluginArchive -RepoRoot $Repo -Component (Get-Alpha) -OutputDirectory (Join-Path $TestDrive 'out') -Repository 'owner/example'
        [IO.Path]::GetFileName($Archive.Path) | Should -Be 'alpha-1.0.0-plugin.zip'
        $Zip = [IO.Compression.ZipFile]::OpenRead($Archive.Path)
        try {
            $Zip.Entries.FullName | Should -Be @('LICENSE', 'instructions/x.instructions.md', 'plugin.json', 'skills/alpha/SKILL.md', 'skills/alpha/skill.metadata.yaml')
            $Manifest = Read-Entry $Zip 'plugin.json' | ConvertFrom-Json -AsHashtable
            $Skill = Read-Entry $Zip 'skills/alpha/SKILL.md'
        }
        finally { $Zip.Dispose() }
        $Link = [IO.Path]::GetFullPath('skills/alpha/../../instructions/x.instructions.md', '/plugin')
        $Link | Should -Be '/plugin/instructions/x.instructions.md'
        @($Manifest.Keys) | Should -Be @('$schema', 'name', 'version', 'description', 'repository', 'keywords', 'extensions')
        $Manifest['$schema'] | Should -Be 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
        $Manifest.name | Should -Be 'alpha'
        $Manifest.version | Should -Be '1.0.0'
        $Manifest.repository | Should -Be 'https://github.com/owner/example'
        $Manifest.keywords | Should -Be @('architecture')
        $Manifest.extensions['io.github.f2calv.skill-library'].required[0].id | Should -Be 'beta'
        (Get-SkillFrontmatter $Skill).metadata['user-invocable'] | Should -Be 'true'
        $Skill | Should -BeLike '*See `[X`](../../instructions/x.instructions.md).*'
    }

    It 'produces identical bytes on rebuild' {
        $First = New-SkillPluginArchive -RepoRoot $Repo -Component (Get-Alpha) -OutputDirectory (Join-Path $TestDrive 'a')
        $Second = New-SkillPluginArchive -RepoRoot $Repo -Component (Get-Alpha) -OutputDirectory (Join-Path $TestDrive 'b')
        $Second.Sha256 | Should -Be $First.Sha256
    }

    It 'omits repository and keywords when there are none' {
        $Beta = Get-SkillComponent -RepoRoot $Repo | Where-Object Id -eq 'beta'
        $Manifest = New-SkillPluginManifest -Component $Beta
        @($Manifest.Keys) | Should -Be @('$schema', 'name', 'version', 'description', 'extensions')
        $Manifest.extensions['io.github.f2calv.skill-library'].required | Should -BeNullOrEmpty
    }

    It 'refuses a skill that opts out' {
        Write-FixtureText $Repo '.github/skills/gamma/skill.metadata.yaml' "version: 1.0.0`nagentPlugin: false`n"
        Invoke-FixtureGit $Repo commit -q -am optout
        $Gamma = Get-SkillComponent -RepoRoot $Repo | Where-Object Id -eq 'gamma'
        { New-SkillPluginArchive -RepoRoot $Repo -Component $Gamma -OutputDirectory (Join-Path $TestDrive 'd') } | Should -Throw '*is not packaged as an Agent Plugin*'
    }

    It 'refuses uncommitted changes' {
        Write-FixtureText $Repo '.github/skills/alpha/SKILL.md' "changed`n"
        { New-SkillPluginArchive -RepoRoot $Repo -Component (Get-Alpha) -OutputDirectory (Join-Path $TestDrive 'e') } | Should -Throw '*commit or stash*'
    }

    It 'rejects an external file outside .github' {
        Write-FixtureText $Repo 'docs/x.md' "# X`n"
        Write-FixtureText $Repo '.github/skills/gamma/skill.metadata.yaml' "version: 1.0.0`nexternalFiles: [docs/x.md]`n"
        Invoke-FixtureGit $Repo add -A
        Invoke-FixtureGit $Repo commit -q -m docs
        $Gamma = Get-SkillComponent -RepoRoot $Repo | Where-Object Id -eq 'gamma'
        { New-SkillPluginArchive -RepoRoot $Repo -Component $Gamma -OutputDirectory (Join-Path $TestDrive 'c') } | Should -Throw "*'docs/x.md' must be under .github/*"
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

    It 'lists an Agent Plugin download only for releases that have one' {
        $Release = @(
            [pscustomobject]@{ Id = 'alpha'; Version = '1.0.0'; Url = 'https://example.com/a.zip'; Sha256 = ('a' * 64); Description = 'A.'; Facets = @(); Required = @(); Related = @()
                PluginUrl = 'https://example.com/a-plugin.zip'; PluginSha256 = ('d' * 64) }
            [pscustomobject]@{ Id = 'beta'; Version = '1.0.0'; Url = 'https://example.com/b.zip'; Sha256 = ('b' * 64); Description = 'B.'; Facets = @(); Required = @(); Related = @() }
        )
        $Catalog = New-SkillCatalog -Release $Release
        $Catalog.extensions['alpha'].skill_library.agent_plugin.download_url | Should -Be 'https://example.com/a-plugin.zip'
        $Catalog.extensions['alpha'].skill_library.agent_plugin.sha256 | Should -Be ('d' * 64)
        $Catalog.extensions['beta'].skill_library.Contains('agent_plugin') | Should -BeFalse
        New-SkillCatalogPage -Catalog $Catalog | Should -BeLike '*href="https://example.com/a-plugin.zip">plugin</a>*'
    }
}
