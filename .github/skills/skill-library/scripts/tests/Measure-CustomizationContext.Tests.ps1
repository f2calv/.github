#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Measure-CustomizationContext.ps1')

    function Write-Fixture {
        param([string]$Path, [string]$Text)
        $Full = Join-Path $TestDrive $Path
        New-Item -ItemType Directory -Path (Split-Path $Full -Parent) -Force | Out-Null
        [IO.File]::WriteAllText($Full, $Text)
    }

    Write-Fixture 'gh/instructions/always.instructions.md' ("---`napplyTo: '**'`n---`n" + ('a' * 400))
    Write-Fixture 'gh/instructions/cs.instructions.md' ("---`napplyTo: '**/*.cs'`n---`n" + ('b' * 800))
    Write-Fixture 'gh/instructions/readme.instructions.md' ("---`napplyTo: '**/README.md,docs/**'`n---`nshort")
    Write-Fixture 'gh/skills/small/SKILL.md' "---`nname: small`ndescription: 'Does a thing. Use when needed.'`n---`n# Small`n"
    Write-Fixture 'gh/skills/large/SKILL.md' ("---`nname: large`ndescription: '" + ('d' * 700) + "'`n---`n" + ('x' * 2000))

    $script:Arguments = @{
        Root              = Join-Path $TestDrive 'gh'
        SamplePath        = @('src/App/Foo.cs', 'README.md', 'src/README.md', 'docs/a/b.md', 'main.tf')
        AlwaysOnBudget    = 1000
        SampleBudget      = 150
        DescriptionBudget = 600
        SkillBudget       = 1024
    }
}

Describe 'ConvertTo-GlobRegex' -Tag 'Unit' {
    It 'matches <Path> against <Glob> as <Expected>' -ForEach @(
        @{ Glob = '**/*.cs'; Path = 'Foo.cs'; Expected = $true }
        @{ Glob = '**/*.cs'; Path = 'src/a/Foo.cs'; Expected = $true }
        @{ Glob = '**/*.cs'; Path = 'src/Foo.csproj'; Expected = $false }
        @{ Glob = 'docs/**'; Path = 'docs/a/b.md'; Expected = $true }
        @{ Glob = 'src/*.yaml'; Path = 'src/a/b.yaml'; Expected = $false }
        @{ Glob = '**/README.md'; Path = 'README.md'; Expected = $true }
    ) {
        ($Path -match (ConvertTo-GlobRegex $Glob)) | Should -Be $Expected
    }
}

Describe 'Measure-CustomizationContext' -Tag 'Unit' {
    BeforeAll {
        $script:Result = Measure-CustomizationContext @script:Arguments
    }

    It 'sums always-on instructions separately from scoped ones' {
        $script:Result.AlwaysOn | Should -Be @('always.instructions.md')
        $script:Result.AlwaysOnTokens | Should -BeGreaterThan 100
    }

    It 'attributes scoped instructions to each sample path' {
        ($script:Result.Samples | Where-Object Path -EQ 'src/App/Foo.cs').Instructions | Should -Be @('cs.instructions.md')
        ($script:Result.Samples | Where-Object Path -EQ 'src/README.md').Instructions | Should -Be @('readme.instructions.md')
        ($script:Result.Samples | Where-Object Path -EQ 'docs/a/b.md').Instructions | Should -Be @('readme.instructions.md')
        ($script:Result.Samples | Where-Object Path -EQ 'main.tf').Tokens | Should -Be 0
    }

    It 'reports every exceeded budget and nothing else' {
        $script:Result.Findings.Count | Should -Be 3
        $script:Result.Findings -join "`n" | Should -BeLike '*src/App/Foo.cs loads*'
        $script:Result.Findings -join "`n" | Should -BeLike '*large description is 700 characters*'
        $script:Result.Findings -join "`n" | Should -BeLike '*large SKILL.md is*'
    }

    It 'ranks the largest skills first' {
        $script:Result.LargestSkills[0].Name | Should -Be 'large'
    }
}
