#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../SkillLibrary.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'SkillLibraryFixture.psm1') -Force
    $Script = Join-Path $PSScriptRoot '../New-SkillMetadata.ps1'
}

Describe 'New-SkillMetadata' -Tag 'Unit' {
    BeforeEach { $Repo = New-SkillFixture $TestDrive }

    It 'scaffolds a valid sidecar from links to other skills and repository files' {
        Write-FixtureSkill $Repo 'dotnet-delta' -Body "See [beta](../beta/SKILL.md), [x](../../instructions/x.instructions.md) and [web](https://example.com).`n"
        & $Script -RepoRoot $Repo 6> $null
        $Metadata = Read-SkillYaml (Join-Path $Repo '.github/skills/dotnet-delta/skill.metadata.yaml')
        $Metadata.version | Should -Be '1.0.0'
        $Metadata.facets | Should -Be @('dotnet')
        $Metadata.related[0].id | Should -Be 'beta'
        $Metadata.related[0].reason | Should -Be 'Linked from SKILL.md.'
        $Metadata.externalFiles | Should -Be @('.github/instructions/x.instructions.md')
        @(Test-SkillComponent -RepoRoot $Repo -Component (Get-SkillComponent -RepoRoot $Repo)) | Should -BeNullOrEmpty
    }

    It 'leaves existing sidecars alone and refuses to overwrite one by name' {
        & $Script -RepoRoot $Repo 6> $null
        Invoke-FixtureGit $Repo diff --exit-code
        { & $Script -RepoRoot $Repo -Id alpha 6> $null } | Should -Throw '*already has skill.metadata.yaml*'
    }

    It 'previews without writing' {
        Write-FixtureSkill $Repo 'delta'
        & $Script -RepoRoot $Repo -WhatIf 6> $null
        Join-Path $Repo '.github/skills/delta/skill.metadata.yaml' | Should -Not -Exist
    }
}
