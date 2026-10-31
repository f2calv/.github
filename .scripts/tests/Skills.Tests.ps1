#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

param(
    [string[]]$SkillName = @()
)

BeforeDiscovery {
    $SkillsRoot = Join-Path $PSScriptRoot '..\..\.github\skills'
    $script:Skills = Get-ChildItem -LiteralPath $SkillsRoot -Directory |
    Where-Object {
        ($SkillName.Count -eq 0 -or $_.Name -in $SkillName) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md'))
    } |
    ForEach-Object { @{ Name = $_.Name; Path = Join-Path $_.FullName 'SKILL.md' } }

    $missing = @($SkillName | Where-Object { $_ -notin $script:Skills.Name })
    if ($missing.Count -gt 0) {
        throw "Requested skills were not found: $($missing -join ', ')."
    }
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

    It 'declares a matching name and a nonempty discovery description' {
        $text = $script:Lines -join "`n"
        $frontmatter = [regex]::Match($text, '\A---\n(.*?)\n---(?:\n|$)', 'Singleline')
        $frontmatter.Success | Should -BeTrue
        $frontmatter.Groups[1].Value | Should -Match "(?m)^name: ['`"]?$([regex]::Escape($Name))['`"]?$"
        $frontmatter.Groups[1].Value | Should -Match '(?m)^description: .*\S'
        $frontmatter.Groups[1].Value | Should -Not -Match '(?m)^applyTo:'
    }

    It 'resolves local Markdown links in the skill and its supporting guides' {
        $root = Split-Path $Path -Parent
        foreach ($document in Get-ChildItem -LiteralPath $root -Filter '*.md' -Recurse) {
            $text = [IO.File]::ReadAllText($document.FullName)
            $text = [regex]::Replace($text, '(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1\s*$', '')
            foreach ($match in [regex]::Matches($text, '\]\(([^)\s]+)(?:\s+"[^"]*")?\)')) {
                $link = $match.Groups[1].Value
                if ($link -match '^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|#|/)') { continue }
                $relative = ($link -split '#', 2)[0]
                if (-not $relative -or $relative -match '[<>]') { continue }
                $target = Join-Path $document.DirectoryName ([uri]::UnescapeDataString($relative))
                Test-Path -LiteralPath $target | Should -BeTrue -Because "$($document.Name) links to $relative"
            }
        }
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
