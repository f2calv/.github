#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\Find-Pii.ps1'
    . $script:ScriptPath

    function Initialize-TestRepository {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $false)]
            [switch]$IncludeSeedFile
        )

        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        & git -C $Path init --quiet
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to initialize the synthetic Git repository.'
        }

        'appsettings.Local.json' | Set-Content -LiteralPath (Join-Path $Path '.gitignore')
        if ($IncludeSeedFile) {
            @{
                Endpoint           = 'https://api.private.invalid'
                Phone              = '+15555550123'
                Address            = '10.20.30.40'
                Storage            = 'https://syntheticacct.blob.core.windows.net/container'
                AzureEntraTenantId = '11111111-2222-3333-4444-555555555555'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Path 'appsettings.Local.json')
        }
    }

    function Add-TestTrackedFile {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RepositoryPath,

            [Parameter(Mandatory = $true)]
            [string]$Content
        )

        $FilePath = Join-Path $RepositoryPath 'tracked.txt'
        $Content | Set-Content -LiteralPath $FilePath
        & git -C $RepositoryPath add .gitignore tracked.txt
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to stage the synthetic test files.'
        }
    }

    Mock Write-Host {}
}

Describe 'Invoke-PiiScan' -Tag 'Unit' {
    It 'Extracts exact synthetic seeds from a local configuration file' {
        $RepositoryPath = Join-Path $TestDrive 'seed-extraction'
        Initialize-TestRepository -Path $RepositoryPath -IncludeSeedFile
        Add-TestTrackedFile -RepositoryPath $RepositoryPath -Content 'No private values here.'

        $Result = Invoke-PiiScan `
            -RepoRoot $RepositoryPath `
            -SeedFile @('appsettings.Local.json')

        $Result.Seeds | Should -Contain 'private.invalid'
        $Result.Seeds | Should -Contain '+15555550123'
        $Result.Seeds | Should -Contain '10.20.30.40'
        $Result.Seeds | Should -Contain 'syntheticacct'
        $Result.Seeds | Should -Contain '11111111-2222-3333-4444-555555555555'
    }

    It 'Classifies working-tree seed and heuristic findings while dropping allowlisted values' {
        $RepositoryPath = Join-Path $TestDrive 'working-tree'
        Initialize-TestRepository -Path $RepositoryPath -IncludeSeedFile
        Add-TestTrackedFile `
            -RepositoryPath $RepositoryPath `
            -Content 'private.invalid user@sample.invalid user@example.com 192.168.1.100'

        $Result = Invoke-PiiScan `
            -RepoRoot $RepositoryPath `
            -SeedFile @('appsettings.Local.json')

        @($Result.Findings.Source | Select-Object -Unique) | Should -Be @('working-tree')
        @($Result.Findings | Where-Object Value -eq 'private.invalid').Confidence | Should -Contain 'seed'
        @($Result.Findings | Where-Object Value -eq 'user@sample.invalid').Confidence | Should -Contain 'heuristic'
        @($Result.Findings | Where-Object Value -eq 'user@example.com').Confidence | Should -Contain 'heuristic'
        @($Result.Findings.Value) | Should -Not -Contain '192.168.1.100'
    }

    It 'Returns no high-confidence hits for heuristic-only findings' {
        $RepositoryPath = Join-Path $TestDrive 'heuristic-only'
        Initialize-TestRepository -Path $RepositoryPath
        Add-TestTrackedFile -RepositoryPath $RepositoryPath -Content 'user@sample.invalid'

        $Result = Invoke-PiiScan -RepoRoot $RepositoryPath -SeedFile @()

        $Result.SeedHits | Should -Be 0
        $Result.HighConfidenceHits | Should -Be 0
        @($Result.Findings).Count | Should -Be 1
    }

    It 'Classifies Windows and Unix user-profile paths as high confidence' {
        $RepositoryPath = Join-Path $TestDrive 'user-profile-paths'
        Initialize-TestRepository -Path $RepositoryPath
        $WindowsPath = 'C:' + '\Users\' + 'sample-user\source\repository'
        $MacPath = '/' + 'Users/sample-user/source/repository'
        $LinuxPath = '/' + 'home/sample-user/source/repository'
        Add-TestTrackedFile -RepositoryPath $RepositoryPath -Content "$WindowsPath $MacPath $LinuxPath"

        $Result = Invoke-PiiScan -RepoRoot $RepositoryPath -SeedFile @()

        $Result.HighConfidenceHits | Should -Be 3
        @($Result.Findings.Confidence | Select-Object -Unique) | Should -Be @('user-path')
    }

    It 'Allows generic container profiles and hidden home directories' {
        $RepositoryPath = Join-Path $TestDrive 'generic-profile-paths'
        Initialize-TestRepository -Path $RepositoryPath
        $ContainerPath = '/' + 'home/vscode/workspace'
        $ApplicationPath = '/' + 'home/app/data'
        $RunnerPath = '/' + 'home/runner/work/repository'
        $HiddenPath = '/' + 'home/.local/share'
        Add-TestTrackedFile -RepositoryPath $RepositoryPath -Content "$ContainerPath $ApplicationPath $RunnerPath $HiddenPath"

        $Result = Invoke-PiiScan -RepoRoot $RepositoryPath -SeedFile @()

        $Result.HighConfidenceHits | Should -Be 0
        @($Result.Findings).Count | Should -Be 0
    }

    It 'Throws when git grep fails' {
        $RepositoryPath = Join-Path $TestDrive 'git-failure'
        Initialize-TestRepository -Path $RepositoryPath
        Mock git {
            $global:LASTEXITCODE = 128
            'fatal: synthetic repository failure'
        }

        {
            Invoke-PiiScan -RepoRoot $RepositoryPath -SeedFile @()
        } | Should -Throw '*git grep failed with exit code 128*synthetic repository failure*'
    }
}


Describe 'Find-Pii script exit behavior' -Tag 'Unit' {
    It 'Returns exit code 1 for FailOnFind when a seeded value is tracked' {
        $RepositoryPath = Join-Path $TestDrive 'fail-on-find'
        Initialize-TestRepository -Path $RepositoryPath -IncludeSeedFile
        Add-TestTrackedFile -RepositoryPath $RepositoryPath -Content 'private.invalid'

        & pwsh -NoProfile -File $script:ScriptPath `
            -RepoRoot $RepositoryPath `
            -SeedFile appsettings.Local.json `
            -FailOnFind *> $null

        $LASTEXITCODE | Should -Be 1
    }

    It 'Returns exit code 0 for FailOnFind when findings are heuristic only' {
        $RepositoryPath = Join-Path $TestDrive 'pass-on-heuristic'
        Initialize-TestRepository -Path $RepositoryPath
        Add-TestTrackedFile -RepositoryPath $RepositoryPath -Content 'user@sample.invalid'

        & pwsh -NoProfile -File $script:ScriptPath `
            -RepoRoot $RepositoryPath `
            -FailOnFind *> $null

        $LASTEXITCODE | Should -Be 0
    }

    It 'Returns exit code 1 for FailOnFind when a user-profile path is tracked' {
        $RepositoryPath = Join-Path $TestDrive 'fail-on-user-profile-path'
        Initialize-TestRepository -Path $RepositoryPath
        $UserPath = 'C:' + '\Users\' + 'sample-user\source\repository'
        Add-TestTrackedFile -RepositoryPath $RepositoryPath -Content $UserPath

        & pwsh -NoProfile -File $script:ScriptPath `
            -RepoRoot $RepositoryPath `
            -FailOnFind *> $null

        $LASTEXITCODE | Should -Be 1
    }
}
