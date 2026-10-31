#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../SkillLibrary.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'SkillLibraryFixture.psm1') -Force
    $Script = Join-Path $PSScriptRoot '../../../../../src/skill-library-extension/scripts/Invoke-SkillLibrary.ps1'
    $SavedPath = $env:PATH
    # Records each call and registers the extension the way specify extension add would.
    New-FakeCommand -Root $TestDrive -Name 'specify' -Script @'
Add-Content -LiteralPath (Join-Path (Get-Location) 'specify.log') -Value "$($args -join ' ') catalog=$env:SPECKIT_CATALOG_URL"
$Registry = Join-Path (Get-Location) '.specify/extensions/.registry'
$Data = Get-Content -Raw -LiteralPath $Registry | ConvertFrom-Json -AsHashtable
$Data.extensions[$args[2]] = @{ version = $args[4]; enabled = $true }
[IO.File]::WriteAllText($Registry, ($Data | ConvertTo-Json -Depth 5))
[void](New-Item -ItemType Directory -Force -Path (Join-Path (Get-Location) ".specify/extensions/$($args[2])/resources/.github/skills/$($args[2])"))
Set-Content -LiteralPath (Join-Path (Get-Location) ".specify/extensions/$($args[2])/resources/.github/skills/$($args[2])/SKILL.md") -Value '# Skill'
exit 0
'@
    $CatalogPath = Join-Path $TestDrive 'catalog.json'
    $Release = @(
        [pscustomobject]@{ Id = 'alpha'; Version = '1.0.0'; Url = 'https://example.com/a1.zip'; Sha256 = ('a' * 64); Description = 'Old alpha.'; Facets = @('architecture')
            Required = @(@{ id = 'beta'; version = '1.0.0' }); Related = @(@{ id = 'gamma'; reason = 'Optional extra.' }) }
        [pscustomobject]@{ Id = 'alpha'; Version = '1.1.0'; Url = 'https://example.com/a2.zip'; Sha256 = ('b' * 64); Description = 'Alpha guidance.'; Facets = @('architecture')
            Required = @(@{ id = 'beta'; version = '1.0.0' }); Related = @(@{ id = 'gamma'; reason = 'Optional extra.' }) }
        [pscustomobject]@{ Id = 'beta'; Version = '1.0.0'; Url = 'https://example.com/b.zip'; Sha256 = ('c' * 64); Description = 'Beta guidance.'; Facets = @(); Required = @(); Related = @() }
        [pscustomobject]@{ Id = 'gamma'; Version = '1.0.0'; Url = 'https://example.com/g.zip'; Sha256 = ('d' * 64); Description = 'Gamma guidance.'; Facets = @('testing')
            Required = @(); Related = @(@{ id = 'alpha'; reason = 'Back link.' }) }
    )
    [IO.File]::WriteAllText($CatalogPath, ((New-SkillCatalog -Release $Release) | ConvertTo-Json -Depth 20))
    # Plain function so @args forwards -Version and -Related as parameters.
    function Invoke-Library { & $Script @args -CatalogUrl $CatalogPath -Workspace $Workspace | Out-String }
}

AfterAll { $env:PATH = $SavedPath }

Describe 'Invoke-SkillLibrary' -Tag 'Unit' {
    BeforeEach {
        $Workspace = Join-Path $TestDrive ([guid]::NewGuid())
        [void][IO.Directory]::CreateDirectory("$Workspace/.specify/extensions")
        [IO.File]::WriteAllText("$Workspace/.specify/extensions/.registry", '{"schema_version":"1.0","extensions":{"skill":{"version":"1.0.0","enabled":true}}}')
    }

    It 'lists commands by default' {
        Invoke-Library | Should -BeLike '*Commands: search*'
    }

    It 'searches IDs, descriptions and facets' {
        $Output = Invoke-Library search architecture
        $Output | Should -Match 'alpha\s+1\.1\.0'
        $Output | Should -Not -Match 'beta'
        Invoke-Library search nothing | Should -BeLike "*can't find a skill matching 'nothing'*"
    }

    It 'plans required skills first and offers related skills' {
        $Output = Invoke-Library plan alpha
        $Output | Should -Match '(?s)beta\s+1\.0\.0\s+install\s+required by alpha.*alpha\s+1\.1\.0\s+install\s+requested'
        $Output | Should -Match 'gamma\s+not installed\s+alpha\s+Optional extra\.'
    }

    It 'plans an exact older version with a selected related skill and reports conflicts' {
        [IO.File]::WriteAllText("$Workspace/.specify/extensions/.registry", '{"schema_version":"1.0","extensions":{"beta":{"version":"0.9.0","enabled":true}}}')
        $Output = Invoke-Library plan alpha -Version 1.0.0 -Related gamma
        $Output | Should -Match 'beta\s+1\.0\.0\s+conflict: 0\.9\.0 installed'
        $Output | Should -Match 'alpha\s+1\.0\.0\s+install'
        $Output | Should -Match 'gamma\s+1\.0\.0\s+install\s+related, selected'
    }

    It 'installs in dependency order through specify with the library catalog' {
        Invoke-Library install alpha -Related gamma | Out-Null
        Get-Content "$Workspace/specify.log" | Should -Be @(
            "extension add beta --version 1.0.0 catalog=$CatalogPath"
            "extension add alpha --version 1.1.0 catalog=$CatalogPath"
            "extension add gamma --version 1.0.0 catalog=$CatalogPath")
        $env:SPECKIT_CATALOG_URL | Should -BeNullOrEmpty
        Invoke-Library install alpha | Out-Null
        @(Get-Content "$Workspace/specify.log").Count | Should -Be 3
    }

    It 'refuses to install over a different installed version' {
        [IO.File]::WriteAllText("$Workspace/.specify/extensions/.registry", '{"schema_version":"1.0","extensions":{"beta":{"version":"0.9.0","enabled":true}}}')
        { Invoke-Library install alpha } | Should -Throw '*Resolve version conflicts first: beta*'
        "$Workspace/specify.log" | Should -Not -Exist
    }

    It 'upgrades installed skills to their latest versions, required skills first' {
        Invoke-Library install alpha -Version 1.0.0 | Out-Null
        Remove-Item "$Workspace/specify.log"
        $Output = Invoke-Library upgrade-all
        $Output | Should -Match '(?s)beta\s+1\.0\.0\s+current.*alpha\s+1\.1\.0\s+upgrade from 1\.0\.0'
        Get-Content "$Workspace/specify.log" | Should -Be "extension add alpha --version 1.1.0 --force catalog=$CatalogPath"
        $env:SPECKIT_CATALOG_URL | Should -BeNullOrEmpty
        Invoke-Library upgrade-all | Should -BeLike '*All installed skills are at their latest versions*'
    }

    It 'reports when no skills are installed to upgrade' {
        Invoke-Library upgrade-all | Should -BeLike '*No skills are installed*'
    }

    It 'lists installed skills and loads their files with SKILL.md first' {
        Invoke-Library install beta | Out-Null
        Invoke-Library list | Should -Match 'beta\s+1\.0\.0\s+True'
        Invoke-Library load beta | Should -BeLike '*.specify/extensions/beta/resources/.github/skills/beta/SKILL.md*'
        { Invoke-Library load gamma } | Should -Throw "*'gamma' is not installed*"
    }

    It 'reports an unknown skill' {
        { Invoke-Library plan missing } | Should -Throw "*can't find the skill 'missing'*"
    }
}
