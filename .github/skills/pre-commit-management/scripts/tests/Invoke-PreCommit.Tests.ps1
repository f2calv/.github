#Requires -Version 7.4

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Invoke-PreCommit.ps1') -RepoRoot $TestDrive
}

Describe 'Get-PreCommitArguments' {
    It 'runs all files by default' {
        Get-PreCommitArguments -Operation Run | Should -Be @('run', '--all-files')
    }

    It 'targets a hook and explicit files' {
        $arguments = Get-PreCommitArguments -Operation Run -SelectedHook markdownlint -SelectedFiles @('README.md', 'docs/example.md')

        $arguments | Should -Be @('run', 'markdownlint', '--files', 'README.md', 'docs/example.md')
    }

    It 'builds the update command' {
        Get-PreCommitArguments -Operation Update | Should -Be @('autoupdate')
    }

    It 'builds the explicit pre-push install command' {
        Get-PreCommitArguments -Operation InstallPrePush | Should -Be @('install', '--hook-type', 'pre-push')
    }

    It 'rejects run-only selectors in update mode' {
        { Get-PreCommitArguments -Operation Update -SelectedHook markdownlint } | Should -Throw
    }
}

Describe 'Resolve-RepositoryRoot' {
    It 'accepts a root containing pre-commit configuration' {
        $repository = Join-Path $TestDrive 'repository'
        $null = New-Item -ItemType Directory -Path $repository
        Set-Content -LiteralPath (Join-Path $repository '.pre-commit-config.yaml') -Value 'repos: []'

        Resolve-RepositoryRoot -Path $repository | Should -Be $repository
    }

    It 'rejects a root without pre-commit configuration' {
        $repository = Join-Path $TestDrive 'missing-config'
        $null = New-Item -ItemType Directory -Path $repository

        { Resolve-RepositoryRoot -Path $repository } | Should -Throw
    }
}

Describe 'Test-PreCommitVersionOutput' {
    It 'accepts the required runtime version' {
        Test-PreCommitVersionOutput -Output 'pre-commit 4.6.2' -RequiredVersion '4.6.2' | Should -BeTrue
    }

    It 'rejects a stale runtime version' {
        Test-PreCommitVersionOutput -Output 'pre-commit 3.7.1' -RequiredVersion '4.6.2' | Should -BeFalse
    }
}
