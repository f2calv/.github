#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeDiscovery {
    $SkillsRoot = Join-Path $PSScriptRoot '..\..\.github\skills'
    $script:Skills = Get-ChildItem -LiteralPath $SkillsRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    ForEach-Object { @{ Name = $_.Name; Path = Join-Path $_.FullName 'SKILL.md' } }
}

Describe 'Skill <Name>' -Tag 'Unit' -ForEach $script:Skills {
    BeforeAll {
        $script:Lines = Get-Content -LiteralPath $Path
        $script:HeadingIndex = @(
            for ($i = 0; $i -lt $script:Lines.Count; $i++) {
                if ($script:Lines[$i] -ceq '## Maintaining This Skill') { $i }
            }
        )
    }

    It 'has exactly one Maintaining This Skill section' {
        $script:HeadingIndex.Count | Should -Be 1
    }

    It 'lists at least one drift trigger in that section' {
        $Section = $script:Lines | Select-Object -Skip ($script:HeadingIndex[0] + 1) |
        ForEach-Object -Begin { $Stop = $false } -Process {
            if ($_ -match '^#{1,2} ') { $Stop = $true }
            if (-not $Stop) { $_ }
        }
        @($Section | Where-Object { $_ -match '^[-*] \S' }).Count | Should -BeGreaterThan 0
    }
}
