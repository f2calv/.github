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

Describe 'Container fallback' {
    BeforeAll {
        function Invoke-FakeContainer {
            $script:containerCalls.Add(@($args))
            $global:LASTEXITCODE = if ($args[0] -eq 'image') { $script:inspectExit } else { $script:commandExit }
        }
    }

    BeforeEach {
        $script:containerCalls = [Collections.Generic.List[object]]::new()
        $script:inspectExit = 1
        $script:commandExit = 0
        Mock Get-Command { [pscustomobject]@{ Source = 'Invoke-FakeContainer' } }
    }

    It 'builds and runs the selected engine with the repository and cache mounts' -ForEach @(
        @{ Engine = 'Docker'; Executable = 'docker' }
        @{ Engine = 'Podman'; Executable = 'podman' }
    ) {
        Invoke-ContainerPreCommit -Arguments @('run', '--all-files') -WorkingDirectory $TestDrive `
            -Image 'localhost/example:local' -Volume 'example_cache' -Version '4.6.2' -Engine $Engine

        Should -Invoke Get-Command -Times 1 -Exactly -ParameterFilter { $Name -eq $Executable }
        $script:containerCalls.Count | Should -Be 3
        $script:containerCalls[1] | Should -Contain 'PRE_COMMIT_VERSION=4.6.2'
        $script:containerCalls[2] | Should -Contain "${TestDrive}:/src"
        $script:containerCalls[2] | Should -Contain 'example_cache:/root/.cache/pre-commit'
        $script:containerCalls[2][-2..-1] | Should -Be @('run', '--all-files')
    }

    It 'does not rebuild an existing fallback image' {
        $script:inspectExit = 0
        Invoke-ContainerPreCommit -Arguments @('run') -WorkingDirectory $TestDrive `
            -Image 'localhost/example:local' -Volume 'example_cache' -Version '4.6.2' -Engine Podman
        $script:containerCalls.Count | Should -Be 2
        $script:containerCalls[1][0] | Should -Be 'run'
    }

    It 'reports a failed fallback build without running hooks' {
        $script:commandExit = 7
        { Invoke-ContainerPreCommit -Arguments @('run') -WorkingDirectory $TestDrive `
                -Image 'localhost/example:local' -Volume 'example_cache' -Version '4.6.2' -Engine Podman } |
            Should -Throw '*Failed to build Podman*'
        $script:containerCalls.Count | Should -Be 2
    }

    It 'reports a failed hook execution' {
        $script:inspectExit = 0
        $script:commandExit = 8
        { Invoke-ContainerPreCommit -Arguments @('run') -WorkingDirectory $TestDrive `
                -Image 'localhost/example:local' -Volume 'example_cache' -Version '4.6.2' -Engine Podman } |
            Should -Throw '*Podman pre-commit exited with code 8*'
    }

    It 'rejects contradictory engine switches through the entry point' {
        $output = & pwsh -NoProfile -File (Join-Path $PSScriptRoot '..\Invoke-PreCommit.ps1') `
            -RepoRoot $TestDrive -ForceDocker -ContainerEngine Podman 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'ForceDocker cannot select Podman'
    }
}
