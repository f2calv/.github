#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\Invoke-DotNetFormatDiagnostics.ps1'
    . $script:ScriptPath
}

Describe 'Get-DotNetFormatSubcommand' -Tag 'Unit' {
    It 'Routes IDE diagnostics to the style formatter' {
        Get-DotNetFormatSubcommand -Diagnostic IDE0040 | Should -BeExactly 'style'
    }

    It 'Routes CA diagnostics to the analyzer formatter' {
        Get-DotNetFormatSubcommand -Diagnostic CA1873 | Should -BeExactly 'analyzers'
    }

    It 'Rejects mixed diagnostic families' {
        { Get-DotNetFormatSubcommand -Diagnostic IDE0040, CA1873 } |
        Should -Throw '*must be run as separate formatter families*'
    }

    It 'Rejects unsupported diagnostic identifiers' {
        { Get-DotNetFormatSubcommand -Diagnostic CS8602 } |
        Should -Throw '*Unsupported diagnostic identifiers*'
    }
}

Describe 'Invoke-DotNetFormatDiagnostics' -Tag 'Unit' {
    BeforeEach {
        $script:Invocations = @()
        Mock Get-TrackedDotNetProject {
            @('C:\synthetic\First.csproj', 'C:\synthetic\Second.csproj')
        }
        Mock Invoke-DotNetFormatCommand {
            param([string[]]$Arguments)
            $script:Invocations += , $Arguments
        }
    }

    It 'Runs IDE diagnostics project by project through style' {
        Invoke-DotNetFormatDiagnostics -RepositoryPath 'C:\synthetic' -Diagnostic IDE0040 -Confirm:$false

        $script:Invocations.Count | Should -Be 2
        $script:Invocations[0] | Should -Be @(
            'format',
            'C:\synthetic\First.csproj',
            'style',
            '--diagnostics',
            'IDE0040',
            '--no-restore',
            '--verbosity',
            'minimal'
        )
    }

    It 'Adds verify mode to every project check' {
        Invoke-DotNetFormatDiagnostics -RepositoryPath 'C:\synthetic' -Diagnostic CA1859, CA1861 -Check

        $script:Invocations.Count | Should -Be 2
        $script:Invocations[0] | Should -Contain 'analyzers'
        $script:Invocations[0] | Should -Contain '--verify-no-changes'
        $script:Invocations[0] | Should -Contain 'CA1859'
        $script:Invocations[0] | Should -Contain 'CA1861'
    }

    It 'Honors WhatIf without invoking dotnet format' {
        Invoke-DotNetFormatDiagnostics -RepositoryPath 'C:\synthetic' -Diagnostic IDE0040 -WhatIf

        $script:Invocations | Should -BeNullOrEmpty
    }
}

Describe 'Get-TrackedDotNetProject' -Tag 'Unit' {
    BeforeEach {
        $script:RepositoryPath = Join-Path $TestDrive 'repository'
        New-Item -ItemType Directory -Path (Join-Path $script:RepositoryPath 'src\Library') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:RepositoryPath 'src\Library\Library.csproj') -Force | Out-Null
        Mock Invoke-GitCommand {
            param([string[]]$Arguments)
            if ($Arguments -contains 'rev-parse') {
                return $script:RepositoryPath
            }

            return 'src/Library/Library.csproj'
        }
    }

    It 'Discovers tracked projects using repository-relative Git paths' {
        $Projects = @(Get-TrackedDotNetProject -RepositoryPath $script:RepositoryPath)

        $Projects | Should -HaveCount 1
        $Projects[0] | Should -BeExactly (Join-Path $script:RepositoryPath 'src\Library\Library.csproj')
    }

    It 'Rejects an explicitly selected untracked project' {
        { Get-TrackedDotNetProject -RepositoryPath $script:RepositoryPath -ProjectPath 'other\Other.csproj' } |
        Should -Throw '*not a tracked .csproj*'
    }
}
