#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Prepare-Documentation.ps1')
    function New-DocumentationFixture {
        $Root = Join-Path $TestDrive ([guid]::NewGuid())
        [void][IO.Directory]::CreateDirectory($Root)
        & git -C $Root init --quiet
        foreach ($Path in @('README.md', '.github/skills/public/SKILL.md', '.github/skills/public/tests/fixture.md')) {
            $Target = Join-Path $Root $Path
            [void][IO.Directory]::CreateDirectory((Split-Path $Target -Parent))
            [IO.File]::WriteAllText($Target, "# Synthetic public document`n")
        }
        [IO.File]::WriteAllText((Join-Path $Root '.gitignore'), ".github/skills/local/`n")
        & git -C $Root add .
        if ($LASTEXITCODE -ne 0) { throw 'Synthetic fixture staging failed.' }
        return $Root
    }
}

Describe 'Tracked documentation preparation' -Tag 'Unit' {
    It 'Includes tracked guidance but never ignored local skills or test fixtures' {
        $Root = New-DocumentationFixture
        $Private = Join-Path $Root '.github/skills/local/SKILL.md'
        [void][IO.Directory]::CreateDirectory((Split-Path $Private -Parent))
        [IO.File]::WriteAllText($Private, 'Synthetic confidential input')

        Invoke-DocumentationPreparation -RepoRoot $Root | Should -Be 2

        (Join-Path $Root '.docs-source/.github/skills/public/SKILL.md') | Should -Exist
        (Join-Path $Root '.docs-source/.github/skills/local/SKILL.md') | Should -Not -Exist
        (Join-Path $Root '.docs-source/.github/skills/public/tests/fixture.md') | Should -Not -Exist
    }

    It 'Removes stale generated files on a repeat preparation' {
        $Root = New-DocumentationFixture
        Invoke-DocumentationPreparation -RepoRoot $Root | Out-Null
        $Stale = Join-Path $Root '.docs-source/stale.md'
        [IO.File]::WriteAllText($Stale, '# Stale output')

        Invoke-DocumentationPreparation -RepoRoot $Root | Should -Be 2

        $Stale | Should -Not -Exist
    }

    It 'Refuses to remove a staging directory it does not own' {
        $Root = New-DocumentationFixture
        [void][IO.Directory]::CreateDirectory((Join-Path $Root '.docs-source'))

        { Invoke-DocumentationPreparation -RepoRoot $Root } | Should -Throw '*not owned by this tool*'
    }
}
