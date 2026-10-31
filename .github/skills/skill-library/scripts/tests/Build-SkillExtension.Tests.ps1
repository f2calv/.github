#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SkillLibraryFixture.psm1') -Force
    $Script = Join-Path $PSScriptRoot '../Build-SkillExtension.ps1'
}

Describe 'Build-SkillExtension' -Tag 'Unit' {
    BeforeEach {
        $Repo = New-SkillFixture $TestDrive
        $Out = Join-Path $TestDrive ([guid]::NewGuid())
    }

    It 'builds only the requested skills' {
        $Result = & $Script -RepoRoot $Repo -Id beta, gamma -OutputDirectory $Out
        $Result.Id | Should -Be @('beta', 'gamma')
        (Get-ChildItem $Out).Name | Should -Be @('beta-1.0.0.zip', 'gamma-1.0.0.zip')
    }

    It 'writes a local catalog pointing at the built archives' {
        $Result = & $Script -RepoRoot $Repo -OutputDirectory $Out -CatalogBaseUrl 'http://localhost:8765/'
        $Catalog = Get-Content -Raw (Join-Path $Out 'catalog.json') | ConvertFrom-Json -AsHashtable
        $Catalog.extensions.Keys | Sort-Object | Should -Be @('alpha', 'beta', 'gamma')
        $Catalog.extensions['alpha'].download_url | Should -Be 'http://localhost:8765/alpha-1.0.0.zip'
        $Catalog.extensions['alpha'].sha256 | Should -Be ($Result | Where-Object Id -eq 'alpha').Sha256
        $Catalog.extensions['alpha'].tags | Should -Be @('architecture')
    }

    It 'rejects an unknown skill' {
        { & $Script -RepoRoot $Repo -Id missing -OutputDirectory $Out } | Should -Throw '*Unknown component: missing*'
    }

    It 'rejects invalid metadata before building' {
        Write-FixtureText $Repo '.github/skills/beta/skill.metadata.yaml' "version: nope`n"
        { & $Script -RepoRoot $Repo -OutputDirectory $Out } | Should -Throw '*Invalid skill metadata*'
    }
}
