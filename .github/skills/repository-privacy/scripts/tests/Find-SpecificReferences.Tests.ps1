#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Find-SpecificReferences.ps1')

    function New-TestFile {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Content
        )

        $Content | Set-Content -LiteralPath (Join-Path $TestDrive $Name)
        return $Name
    }

    function Invoke-TestScan {
        param(
            [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Content,
            [string]$Name = 'guide.md',
            [switch]$IncludeAmbiguous
        )

        $repositories = @(
            [pscustomobject]@{ Name = 'Example.Shared'; Visibility = 'PUBLIC' }
            [pscustomobject]@{ Name = 'secret-gitops'; Visibility = 'PRIVATE' }
            [pscustomobject]@{ Name = 'rust'; Visibility = 'PRIVATE' }
            [pscustomobject]@{ Name = '.github'; Visibility = 'PUBLIC' }
            [pscustomobject]@{ Name = 'guidance'; Visibility = 'PUBLIC' }
            [pscustomobject]@{ Name = 'Upstream.Library'; Visibility = 'PUBLIC'; IsFork = $true }
            [pscustomobject]@{ Name = 'Logging.Library'; Visibility = 'PUBLIC' }
        )
        $seeds = Get-ReferenceSeed -Owner 'octo-owner' -Repository $repositories -SelfRepository 'guidance' `
            -AuthorName 'Pat Example' -Term @('lab.invalid') -IgnoreName @('Logging.Library') `
            -IncludeAmbiguous:$IncludeAmbiguous
        $file = New-TestFile -Name $Name -Content $Content
        return , (Find-SpecificReference -RepoRoot $TestDrive -File @($file) -Seed $seeds)
    }
}

Describe 'Find-SpecificReference' -Tag 'Unit' {
    It 'Reports a private repository name as an error' {
        $findings = Invoke-TestScan -Content 'Deploy through secret-gitops after the merge.'

        $findings.Count | Should -Be 1
        $findings[0].Severity | Should -Be 'Error'
        $findings[0].Kind | Should -Be 'PrivateRepository'
    }

    It 'Reports the author name and caller terms as errors' {
        $findings = Invoke-TestScan -Content 'Written by Pat Example on host01.lab.invalid.'

        @($findings | ForEach-Object Kind) | Should -Be @('AuthorName', 'Term')
        @($findings | Where-Object Severity -ne 'Error').Count | Should -Be 0
    }

    It 'Reviews a public repository named outside example wording' {
        $findings = Invoke-TestScan -Content 'Use Example.Shared for cached reads.'

        $findings.Count | Should -Be 1
        $findings[0].Severity | Should -Be 'Review'
    }

    It 'Accepts a public repository framed as an example on the same or previous line' -TestCases @(
        @{ Content = @('Use a shared caching library, for example Example.Shared.') }
        @{ Content = @('Use a shared caching library such as the public', 'Example.Shared package.') }
    ) {
        param($Content)

        (Invoke-TestScan -Content $Content).Count | Should -Be 0
    }

    It 'Accepts public references inside a real-world example section only' {
        $findings = Invoke-TestScan -Content @(
            '## Real-World Example'
            ''
            'octo-owner/Example.Shared releases first.'
            ''
            '### Wave Detail'
            'Example.Shared again.'
            ''
            '## Maintaining'
            'Keep Example.Shared aligned.'
        )

        $findings.Count | Should -Be 1
        $findings[0].Line | Should -Be 9
    }

    It 'Accepts every public reference in a real-world example file' {
        (Invoke-TestScan -Name 'real-world-example.md' -Content 'Example.Shared and octo-owner.').Count | Should -Be 0
    }

    It 'Reports an owner-prefixed repository once and ignores the scanned repository' {
        $findings = Invoke-TestScan -Content 'See octo-owner/Example.Shared and octo-owner/guidance.'

        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -Be 'PublicRepository'
    }

    It 'Matches a dot-prefixed repository only with its owner' {
        $findings = Invoke-TestScan -Content @('Edit .github/workflows/ci.yml.', 'Clone octo-owner/.github first.')

        $findings.Count | Should -Be 1
        $findings[0].Line | Should -Be 2
    }

    It 'Matches a single-word repository name bare only when requested' {
        $content = 'Follow the rust instructions.'

        (Invoke-TestScan -Content $content).Count | Should -Be 0
        (Invoke-TestScan -Content $content -IncludeAmbiguous)[0].Kind | Should -Be 'PrivateRepository'
    }

    It 'Matches a single-word repository name with its owner prefix' {
        $findings = Invoke-TestScan -Content 'Clone octo-owner/rust first.'

        $findings.Count | Should -Be 1
        $findings[0].Severity | Should -Be 'Error'
    }

    It 'Skips forks and ignored names' {
        (Invoke-TestScan -Content 'Configure Upstream.Library and Logging.Library.').Count | Should -Be 0
    }

    It 'Accepts later mentions of a name the file introduced as an example' {
        $findings = Invoke-TestScan -Content @(
            'Keep Example.Shared aligned.'
            'Use a shared library, for example Example.Shared.'
            ''
            'Example.Shared opens one connection.'
        )

        $findings.Count | Should -Be 1
        $findings[0].Line | Should -Be 1
    }
}
