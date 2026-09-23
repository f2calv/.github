#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    $repositoryRoot = Join-Path $TestDrive 'example-repository'
    New-Item -ItemType Directory -Path $repositoryRoot | Out-Null
    Set-Content (Join-Path $repositoryRoot 'Dockerfile.Debug') "COPY deps/Shared.One /src/Shared.One`nCOPY deps/Shared.Two /src/Shared.Two`nCOPY deps/Shared.One /again"
    . (Join-Path $PSScriptRoot '../Invoke-Build.ps1') -RepositoryRoot $repositoryRoot -BuildMode Application
}

Describe 'Invoke-Build profiles' {
    It 'discovers unique Dockerfile dependencies' {
        Get-DependencyRepositories (Join-Path $repositoryRoot 'Dockerfile.Debug') | Should -Be @('Shared.One', 'Shared.Two')
    }

    It 'uses application defaults' {
        $settings = Resolve-BuildSettings Application $repositoryRoot $null $null $null
        $settings.Configuration | Should -Be 'Debug'
        $settings.Platforms | Should -Be 'linux/amd64,linux/arm64,linux/arm/v7'
        $settings.ImageName | Should -Be 'example-repository'
    }

    It 'uses SignalCli release defaults' {
        $settings = Resolve-BuildSettings SignalCli $repositoryRoot $null $null $null
        $settings.Configuration | Should -Be 'Release'
        $settings.Platforms | Should -Be 'linux/amd64,linux/arm64'
    }

    It 'uses yamlizr release and host-platform defaults' {
        $settings = Resolve-BuildSettings Yamlizr $repositoryRoot $null $null 'yamlizr'
        $settings.Configuration | Should -Be 'Release'
        $settings.Platforms | Should -Match '^linux/(amd64|arm64|arm/v7)$'
    }

    It 'uses multi-arch environment overrides' {
        $previousPlatform = $env:PLATFORM
        try {
            $env:PLATFORM = 'linux/arm64'
            $settings = Resolve-BuildSettings MultiArch $repositoryRoot $null $null $null
            $settings.Platforms | Should -Be 'linux/arm64'
            $settings.BuilderName | Should -Be 'examplerepository'
        }
        finally { $env:PLATFORM = $previousPlatform }
    }

    It 'normalizes explicit tags without resolving GitVersion' {
        Resolve-BuildTag -ExplicitTag 'Feature.TEST' -Push -RepositoryRoot $repositoryRoot | Should -Be 'feature.test'
    }

    It 'rejects pushed yamlizr Debug images' {
        $settings = [pscustomobject]@{ Configuration = 'Debug'; ImageName = 'yamlizr'; RepositoryName = 'yamlizr'; BuilderName = 'yamlizr1'; Platforms = 'linux/amd64' }
        { Invoke-StandardBuild $settings $repositoryRoot Yamlizr 'test' '1.0.0' '' '' -Push } | Should -Throw '*must not be pushed*'
    }

    It 'does not invoke Docker under WhatIf' {
        Mock Invoke-StandardBuild
        Invoke-ContainerBuild -WhatIf
        Should -Invoke Invoke-StandardBuild -Times 0
    }

    It 'builds an application Release image through Docker Buildx' {
        $settings = [pscustomobject]@{ Configuration = 'Release'; ImageName = 'example'; RepositoryName = 'example'; BuilderName = 'example1'; Platforms = 'linux/amd64' }
        Mock Resolve-BuildTag { 'test-tag' }
        Mock Initialize-BuildxBuilder
        Mock git { $global:LASTEXITCODE = 0; if ($args -contains 'branch') { 'main' } else { 'abc123' } }
        Mock docker { $global:LASTEXITCODE = 0 }
        Invoke-StandardBuild $settings $repositoryRoot Application 'test-tag' $null 'Worker' $null
        Should -Invoke docker -ParameterFilter { $args -contains 'build' -and $args -contains 'WORKLOAD=Worker' }
    }

    It 'mirrors dependencies for an application Debug image' {
        $settings = [pscustomobject]@{ Configuration = 'Debug'; ImageName = 'example'; RepositoryName = 'example'; BuilderName = 'example1'; Platforms = 'linux/amd64' }
        Mock Resolve-BuildTag { 'latest-dev' }
        Mock Get-DependencyRepositories { @('Shared.One') }
        Mock Sync-Dependencies
        Mock Initialize-BuildxBuilder
        Mock git { $global:LASTEXITCODE = 0; 'value' }
        Mock docker { $global:LASTEXITCODE = 0 }
        Invoke-StandardBuild $settings $repositoryRoot Application $null $null 'Worker' $null
        Should -Invoke Sync-Dependencies -Times 1 -ParameterFilter { $DependencyRepositories -contains 'Shared.One' }
    }

    It 'builds and smoke-tests a local yamlizr image' {
        $settings = [pscustomobject]@{ Configuration = 'Release'; ImageName = 'yamlizr'; RepositoryName = 'yamlizr'; BuilderName = 'yamlizr1'; Platforms = 'linux/amd64' }
        Mock Resolve-YamlizrVersion { '1.2.3' }
        Mock Resolve-BuildTag { 'latest-dev' }
        Mock Initialize-BuildxBuilder
        Mock Invoke-YamlizrSmokeTest
        Mock git { $global:LASTEXITCODE = 0; 'value' }
        Mock docker { $global:LASTEXITCODE = 0 }
        Invoke-StandardBuild $settings $repositoryRoot Yamlizr $null $null $null $null
        Should -Invoke Invoke-YamlizrSmokeTest -Times 1 -ParameterFilter { $ExpectedVersion -eq '1.2.3' }
    }

    It 'builds a SignalCli image with its project argument' {
        $settings = [pscustomobject]@{ Configuration = 'Release'; ImageName = 'signalcli'; RepositoryName = 'signalcli'; BuilderName = 'signalcli1'; Platforms = 'linux/amd64' }
        Mock Resolve-BuildTag { 'latest-dev' }
        Mock Initialize-BuildxBuilder
        Mock git { $global:LASTEXITCODE = 0; 'value' }
        Mock docker { $global:LASTEXITCODE = 0 }
        Invoke-StandardBuild $settings $repositoryRoot SignalCli $null $null $null 'samples/Host.csproj'
        Should -Invoke docker -ParameterFilter { $args -contains 'PROJECT=samples/Host.csproj' }
    }

    It 'builds a multi-arch output without starting an interactive container' {
        $settings = [pscustomobject]@{ RepositoryName = 'example'; BuilderName = 'example'; Platforms = 'linux/amd64,linux/arm64' }
        $previousOutput = $env:OUTPUT
        try {
            $env:OUTPUT = '--output=type=oci,dest=example.tar'
            Mock Initialize-BuildxBuilder
            Mock git { $global:LASTEXITCODE = 0; 'value' }
            Mock docker { $global:LASTEXITCODE = 0 }
            Invoke-MultiArchBuild $settings $repositoryRoot
            Should -Invoke docker -ParameterFilter { $args -contains '--output=type=oci,dest=example.tar' }
        }
        finally { $env:OUTPUT = $previousOutput }
    }

    It 'uses a requested yamlizr version without GitVersion' {
        Resolve-YamlizrVersion -RequestedVersion '2.3.4' -RepositoryRoot $repositoryRoot | Should -Be '2.3.4'
    }

    It 'falls back to a local yamlizr version when GitVersion is unavailable' {
        Mock Install-GitVersion { $false }
        Resolve-YamlizrVersion -RepositoryRoot $repositoryRoot | Should -Be '0.0.1'
    }

    It 'rejects a Dockerfile without sibling dependencies' {
        $dockerfile = Join-Path $repositoryRoot 'Dockerfile.Empty'
        Set-Content $dockerfile 'FROM scratch'
        { Get-DependencyRepositories $dockerfile } | Should -Throw '*No sibling dependencies*'
    }

    It 'authenticates Docker to GHCR through GitHub CLI' {
        Mock Get-Command { [pscustomobject]@{ Name = 'gh' } }
        Mock gh { $global:LASTEXITCODE = 0; if ($args -contains 'status') { 'write:packages' } elseif ($args -contains 'user') { 'example-user' } else { 'token' } }
        Mock docker { $global:LASTEXITCODE = 0 }
        Connect-Ghcr
        Should -Invoke docker -ParameterFilter { $args -contains 'login' -and $args -contains 'example-user' }
    }

    It 'creates and selects a missing Buildx builder' {
        $script:inspectComplete = $false
        Mock docker {
            if ($args -contains 'inspect' -and -not $script:inspectComplete) {
                $script:inspectComplete = $true
                $global:LASTEXITCODE = 1
                return
            }
            $global:LASTEXITCODE = 0
        }
        Initialize-BuildxBuilder -BuilderName 'example1' -Bootstrap
        Should -Invoke docker -ParameterFilter { $args -contains 'create' -and $args -contains '--bootstrap' }
        Should -Invoke docker -ParameterFilter { $args -contains 'use' }
    }

    It 'accepts a successful yamlizr smoke test' {
        Mock docker { $global:LASTEXITCODE = 0; if ($args -contains '--version') { '1.2.3+abc' } }
        Invoke-YamlizrSmokeTest -Image 'example:latest' -ExpectedVersion '1.2.3'
        Should -Invoke docker -Times 2
    }

    It 'mirrors a sibling dependency on Windows' -Skip:(-not $IsWindows) {
        $dependency = Join-Path (Split-Path $repositoryRoot -Parent) 'Shared.Copy'
        New-Item -ItemType Directory -Path $dependency -Force | Out-Null
        Mock robocopy { $global:LASTEXITCODE = 1 }
        Sync-Dependencies -RepositoryRoot $repositoryRoot -DependencyRepositories @('Shared.Copy')
        Should -Invoke robocopy -Times 1
    }
}
