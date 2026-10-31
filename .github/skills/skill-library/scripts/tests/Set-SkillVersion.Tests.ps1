#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../SkillLibrary.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'SkillLibraryFixture.psm1') -Force
    $Script = Join-Path $PSScriptRoot '../Set-SkillVersion.ps1'
    function Get-Version([string]$Id) { (Read-SkillYaml (Join-Path $Repo ".github/skills/$Id/skill.metadata.yaml")).version }
}

Describe 'Set-SkillVersion' -Tag 'Unit' {
    BeforeEach {
        $Repo = New-SkillFixture $TestDrive
        foreach ($Id in 'alpha', 'beta', 'gamma') { Invoke-FixtureGit $Repo tag "$Id/1.0.0" }
    }

    It 'bumps a changed skill once and cascades the pin and a patch bump to dependents' {
        Write-FixtureText $Repo '.github/skills/beta/SKILL.md' "---`nname: beta`ndescription: Changed.`n---`n"
        & $Script -RepoRoot $Repo -Bump minor 6> $null
        & $Script -RepoRoot $Repo -Id beta -Bump minor 6> $null
        Get-Version 'beta' | Should -Be '1.1.0'
        Get-Version 'alpha' | Should -Be '1.0.1'
        Get-Version 'gamma' | Should -Be '1.0.0'
        (Read-SkillYaml (Join-Path $Repo '.github/skills/alpha/skill.metadata.yaml')).required[0].version | Should -Be '1.1.0'
        @(Test-SkillVersion -RepoRoot $Repo -Component (Get-SkillComponent -RepoRoot $Repo)) | Should -BeNullOrEmpty
    }

    It 'does nothing when no released skill changed' {
        & $Script -RepoRoot $Repo 6> $null
        Invoke-FixtureGit $Repo diff --exit-code
    }

    It 'refuses to bump an unreleased skill, however often it is named' {
        $Repo = New-SkillFixture $TestDrive
        & $Script -RepoRoot $Repo -Id beta 6> $null 3> $null
        & $Script -RepoRoot $Repo -Id beta 6> $null 3> $null
        Get-Version 'beta' | Should -Be '1.0.0'
        Get-Version 'alpha' | Should -Be '1.0.0'
        Invoke-FixtureGit $Repo diff --exit-code
    }

    It 'preserves comments' {
        Write-FixtureText $Repo '.github/skills/gamma/skill.metadata.yaml' "# keep me`nversion: 1.0.0`n"
        & $Script -RepoRoot $Repo -Id gamma 6> $null
        Get-Content -Raw (Join-Path $Repo '.github/skills/gamma/skill.metadata.yaml') | Should -Be "# keep me`nversion: 1.0.1`n"
    }

    It 'rejects an unknown skill' {
        { & $Script -RepoRoot $Repo -Id missing 6> $null } | Should -Throw "*Unknown component 'missing'*"
    }
}
