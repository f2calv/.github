#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    $repositoryRoot = Join-Path $TestDrive 'example-repository'
    New-Item -ItemType Directory -Path $repositoryRoot | Out-Null
    Set-Content (Join-Path $repositoryRoot 'Dockerfile.Debug') "COPY deps/Shared.One /src/Shared.One`nCOPY deps/Shared.Two /src/Shared.Two`nCOPY deps/Shared.One /again"
    . (Join-Path $PSScriptRoot '../Invoke-Build.ps1') -RepositoryRoot $repositoryRoot
    $releaseRoot = Join-Path $TestDrive 'release-only'
    New-Item -ItemType Directory -Path $releaseRoot | Out-Null
}

Describe 'Invoke-Build' {
    It 'discovers unique Dockerfile dependencies' {
        Get-DependencyRepositories (Join-Path $repositoryRoot 'Dockerfile.Debug') | Should -Be @('Shared.One', 'Shared.Two')
    }

    It 'defaults to a Debug multi-platform build when a Debug Dockerfile exists' {
        $settings = Resolve-BuildSettings -RepositoryRoot $repositoryRoot
        $settings.Configuration | Should -Be 'Debug'
        $settings.Platforms | Should -Be 'linux/amd64,linux/arm64,linux/arm/v7'
        $settings.ImageName | Should -Be 'example-repository'
        $settings.BuilderName | Should -Be 'example-repository1'
    }

    It 'defaults to Release without a Debug Dockerfile' {
        (Resolve-BuildSettings -RepositoryRoot $releaseRoot).Configuration | Should -Be 'Release'
    }

    It 'loads the host platform by default' {
        (Resolve-BuildSettings -RepositoryRoot $repositoryRoot -Load).Platforms | Should -Match '^linux/(amd64|arm64|arm/v7)$'
    }

    It 'rejects loading several platforms' {
        { Resolve-BuildSettings -RepositoryRoot $repositoryRoot -Load -Platforms 'linux/amd64,linux/arm64' } |
            Should -Throw '*cannot be loaded*'
    }

    It 'rejects combining push and load' {
        { Resolve-BuildSettings -RepositoryRoot $repositoryRoot -Push -Load } | Should -Throw '*-Push cannot be combined*'
    }

    It 'normalizes explicit tags without resolving GitVersion' {
        Resolve-BuildTag -ExplicitTag 'Feature.TEST' -Push -RepositoryRoot $repositoryRoot | Should -Be 'feature.test'
    }

    It 'does not invoke Docker under WhatIf' {
        Mock Invoke-ImageBuild
        Invoke-ContainerBuild -WhatIf
        Should -Invoke Invoke-ImageBuild -Times 0
    }

    It 'builds a Release image under the origin owner through Docker Buildx' {
        $settings = [pscustomobject]@{ Configuration = 'Release'; ImageName = 'example'; RepositoryName = 'example'; BuilderName = 'example1'; Platforms = 'linux/amd64' }
        Mock Resolve-Version { '1.2.3' }
        Mock Get-GitHubOwner { 'owner' }
        Mock Initialize-BuildxBuilder
        Mock git { $global:LASTEXITCODE = 0; if ($args -contains 'branch') { 'main' } else { 'abc123' } }
        Mock docker { $global:LASTEXITCODE = 0 }
        Invoke-ImageBuild $settings $repositoryRoot 'test-tag' $null 'Worker'
        Should -Invoke docker -ParameterFilter {
            $args -contains 'build' -and $args -contains 'ghcr.io/owner/example:test-tag' -and
            $args -contains 'WORKLOAD=Worker' -and $args -contains 'VERSION=1.2.3' -and
            -not ($args -contains '--load') -and -not ($args -contains '--push')
        }
    }

    It 'uses the Dockerfile workload default without an assembly override' {
        $settings = [pscustomobject]@{ Configuration = 'Release'; ImageName = 'example'; RepositoryName = 'example'; BuilderName = 'example1'; Platforms = 'linux/amd64' }
        Mock Resolve-Version { '1.2.3' }
        Mock Get-GitHubOwner { 'owner' }
        Mock Initialize-BuildxBuilder
        Mock git { $global:LASTEXITCODE = 0; 'value' }
        Mock docker { $global:LASTEXITCODE = 0 }

        Invoke-ImageBuild $settings $repositoryRoot $null $null $null

        Should -Invoke docker -ParameterFilter {
            $args -contains 'build' -and -not @($args | Where-Object { $_ -like 'WORKLOAD=*' })
        }
    }

    It 'mirrors dependencies for a Debug image' {
        $settings = [pscustomobject]@{ Configuration = 'Debug'; ImageName = 'example'; RepositoryName = 'example'; BuilderName = 'example1'; Platforms = 'linux/amd64' }
        Mock Resolve-Version { '1.2.3' }
        Mock Get-GitHubOwner { 'owner' }
        Mock Get-DependencyRepositories { @('Shared.One') }
        Mock Sync-Dependencies
        Mock Initialize-BuildxBuilder
        Mock git { $global:LASTEXITCODE = 0; 'value' }
        Mock docker { $global:LASTEXITCODE = 0 }
        Invoke-ImageBuild $settings $repositoryRoot $null $null 'Worker'
        Should -Invoke Sync-Dependencies -Times 1 -ParameterFilter { $DependencyRepositories -contains 'Shared.One' }
    }

    It 'loads and runs a local image' {
        $settings = [pscustomobject]@{ Configuration = 'Release'; ImageName = 'example'; RepositoryName = 'example'; BuilderName = 'example1'; Platforms = 'linux/amd64' }
        Mock Resolve-Version { '1.2.3' }
        Mock Get-GitHubOwner { 'owner' }
        Mock Initialize-BuildxBuilder
        Mock git { $global:LASTEXITCODE = 0; 'value' }
        Mock docker { $global:LASTEXITCODE = 0 }
        Invoke-ImageBuild $settings $repositoryRoot $null $null $null -Run
        Should -Invoke docker -ParameterFilter { $args -contains 'build' -and $args -contains '--load' }
        Should -Invoke docker -ParameterFilter { $args -contains 'run' -and $args -contains 'ghcr.io/owner/example:latest-dev' }
    }

    It 'derives the GHCR owner from an SSH or HTTPS origin' -ForEach @(
        @{ Url = 'git@github.com:Example-Owner/example.git' }
        @{ Url = 'https://github.com/Example-Owner/example' }
    ) {
        Mock git { $global:LASTEXITCODE = 0; $Url }
        Get-GitHubOwner -RepositoryRoot $repositoryRoot | Should -Be 'example-owner'
    }

    It 'rejects a non-GitHub origin' {
        Mock git { $global:LASTEXITCODE = 0; 'https://example.com/owner/example.git' }
        { Get-GitHubOwner -RepositoryRoot $repositoryRoot } | Should -Throw '*GitHub owner*'
    }

    It 'uses a requested version without GitVersion' {
        Resolve-Version -RequestedVersion '2.3.4' -RepositoryRoot $repositoryRoot | Should -Be '2.3.4'
    }

    It 'falls back to a local version when GitVersion is unavailable' {
        Mock Install-GitVersion { $false }
        Resolve-Version -RepositoryRoot $repositoryRoot | Should -Be '0.0.1'
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
        Initialize-BuildxBuilder -BuilderName 'example1'
        Should -Invoke docker -ParameterFilter { $args -contains 'create' -and $args -contains 'example1' }
        Should -Invoke docker -ParameterFilter { $args -contains 'use' }
    }

    It 'mirrors a sibling dependency on Windows' -Skip:(-not $IsWindows) {
        $dependency = Join-Path (Split-Path $repositoryRoot -Parent) 'Shared.Copy'
        New-Item -ItemType Directory -Path $dependency -Force | Out-Null
        Mock robocopy { $global:LASTEXITCODE = 1 }
        Sync-Dependencies -RepositoryRoot $repositoryRoot -DependencyRepositories @('Shared.Copy')
        Should -Invoke robocopy -Times 1
    }
}
