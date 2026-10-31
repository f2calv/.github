#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Install-Specify.ps1')
    # Stand-ins so Pester can mock the tools on runners where they are not installed.
    function uv { }
    function specify { }
}

Describe 'Install-Specify' -Tag 'Unit' {
    BeforeEach {
        $SavedPath = $env:PATH
        Mock uv { $global:LASTEXITCODE = 0 }
        Mock specify { $global:LASTEXITCODE = 0 }
    }

    AfterEach { $env:PATH = $SavedPath }

    It 'installs the exact tagged release and verifies it' {
        Install-Specify -Version '1.2.3'
        Should -Invoke uv -Times 1 -Exactly -ParameterFilter {
            ($args -join ' ') -eq 'tool install --force specify-cli --from git+https://github.com/github/spec-kit.git@v1.2.3'
        }
        Should -Invoke specify -Times 1 -Exactly -ParameterFilter { $args[0] -eq 'version' }
    }

    It 'rejects a version that is not exact: <Version>' -ForEach @(
        @{ Version = '' }, @{ Version = 'latest' }, @{ Version = '1.2' }, @{ Version = '>=1.2.3' }
    ) {
        { Install-Specify -Version $Version } | Should -Throw '*exact published Specify CLI version*'
        Should -Invoke uv -Times 0 -Exactly
    }

    It 'fails when <Tool> fails' -ForEach @(
        @{ Tool = 'uv'; Expected = '*installation failed*' }
        @{ Tool = 'specify'; Expected = '*version check failed*' }
    ) {
        Mock $Tool { $global:LASTEXITCODE = 1 }
        { Install-Specify -Version '1.2.3' } | Should -Throw $Expected
    }
}
