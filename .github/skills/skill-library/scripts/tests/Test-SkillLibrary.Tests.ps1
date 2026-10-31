#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SkillLibraryFixture.psm1') -Force
    $Script = Join-Path $PSScriptRoot '../Test-SkillLibrary.ps1'
    function Invoke-Check([string[]]$Arguments = @()) {
        $Output = & pwsh -NoProfile -File $Script -RepoRoot $Repo @Arguments 2>&1
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $Output -join "`n" }
    }
}

Describe 'Test-SkillLibrary' -Tag 'Unit' {
    BeforeEach {
        $Repo = New-SkillFixture $TestDrive
        $Changed = "---`nname: gamma`ndescription: Changed.`n---`n"
    }

    It 'passes a consistent repository' {
        $Result = Invoke-Check
        $Result.ExitCode | Should -Be 0
        $Result.Output | Should -BeLike '*3 components are valid.*'
    }

    It 'fails with an actionable message for an unbumped change' {
        Invoke-FixtureGit $Repo tag 'gamma/1.0.0'
        Write-FixtureText $Repo '.github/skills/gamma/SKILL.md' $Changed
        $Result = Invoke-Check
        $Result.ExitCode | Should -Be 1
        $Result.Output | Should -BeLike '*gamma: changed since gamma/1.0.0; run Set-SkillVersion.ps1 -Id gamma.*'
    }

    It 'skips the version check when asked' {
        Invoke-FixtureGit $Repo tag 'gamma/1.0.0'
        Write-FixtureText $Repo '.github/skills/gamma/SKILL.md' $Changed
        (Invoke-Check @('-SkipVersionCheck')).ExitCode | Should -Be 0
    }

    It 'fails for a skill without a sidecar' {
        Write-FixtureSkill $Repo 'delta'
        $Result = Invoke-Check
        $Result.ExitCode | Should -Be 1
        $Result.Output | Should -BeLike '*delta: missing skill.metadata.yaml; run New-SkillMetadata.ps1 -Id delta.*'
    }
}
