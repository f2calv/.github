#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../../../../.devcontainer/Initialize-DevContainer.ps1')
    function uv { $global:LASTEXITCODE = 0 }
    function specify { $global:LASTEXITCODE = 0 }
    function python { $global:LASTEXITCODE = 0 }
    function pre-commit { $global:LASTEXITCODE = 0 }
    function gh { $global:LASTEXITCODE = 0 }
    function node { $global:LASTEXITCODE = 0 }
    function git { $global:LASTEXITCODE = 0 }
}

Describe 'Dev Container preparation' -Tag 'Unit' {
    BeforeEach {
        $script:originalPath = $env:PATH
        $script:originalVersion = $env:SPECIFY_CLI_VERSION
        $env:SPECIFY_CLI_VERSION = '1.2.3'
        Mock uv { $global:LASTEXITCODE = 0 }
        Mock specify { $global:LASTEXITCODE = 0 }
        Mock python { $global:LASTEXITCODE = 0 }
        Mock pre-commit { $global:LASTEXITCODE = 0 }
        Mock gh { $global:LASTEXITCODE = 0 }
        Mock node { $global:LASTEXITCODE = 0 }
        Mock git { $global:LASTEXITCODE = 0 }
    }

    AfterEach {
        $env:PATH = $script:originalPath
        $env:SPECIFY_CLI_VERSION = $script:originalVersion
    }

    It 'installs the exact pin through uv and only requests version output from Specify' {
        Install-Specify -Version $env:SPECIFY_CLI_VERSION | Out-Null
        $output = Initialize-DevContainer -Tools @('pre-commit', 'gh', 'node', 'python', 'uv', 'git')
        "$output" | Should -Match 'Pester 5\.7\.1'
        Should -Invoke uv -Times 1 -Exactly -ParameterFilter {
            ($args -join ' ') -eq 'tool install --force specify-cli --from git+https://github.com/github/spec-kit.git@v1.2.3'
        }
        Should -Invoke specify -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -eq 'version' }
        Should -Invoke specify -Times 1 -Exactly
        ($env:PATH -split [regex]::Escape([IO.Path]::PathSeparator))[0] |
            Should -Be (Join-Path $HOME '.local/bin')
    }

    It 'can prepare the same pinned tool repeatedly without initializing a repository' {
        Install-Specify -Version $env:SPECIFY_CLI_VERSION | Out-Null
        Install-Specify -Version $env:SPECIFY_CLI_VERSION | Out-Null
        Should -Invoke uv -Times 2 -Exactly -ParameterFilter { $args[0] -eq 'tool' }
        Should -Invoke specify -Times 2 -Exactly -ParameterFilter { ($args -join ' ') -eq 'version' }
    }

    It 'rejects an absent or non-exact version before installation' -ForEach @(
        @{ Version = '' }, @{ Version = 'latest' }, @{ Version = '1.2' }
    ) {
        $env:SPECIFY_CLI_VERSION = $Version
        { Install-Specify -Version $env:SPECIFY_CLI_VERSION } | Should -Throw '*exact published*version*'
        Should -Invoke uv -Times 0 -Exactly
    }

    It 'stops when uv installation fails' {
        Mock uv { $global:LASTEXITCODE = 9 }
        { Install-Specify -Version $env:SPECIFY_CLI_VERSION } | Should -Throw '*installation failed with exit code 9*'
        Should -Invoke specify -Times 0 -Exactly
    }

    It 'rejects a failed tool version check' -ForEach @(
        @{ Tool = 'pre-commit' }, @{ Tool = 'gh' }, @{ Tool = 'node' },
        @{ Tool = 'python' }, @{ Tool = 'uv' }, @{ Tool = 'git' }, @{ Tool = 'specify' }
    ) {
        Mock $Tool { $global:LASTEXITCODE = 7 } -ParameterFilter { $args[0] -ne 'tool' }
        if ($Tool -eq 'specify') {
            { Install-Specify -Version $env:SPECIFY_CLI_VERSION } | Should -Throw '*version check failed*'
        }
        else {
            { Initialize-DevContainer -Tools @($Tool) } | Should -Throw '*version check failed with exit code 7*'
        }
    }
}