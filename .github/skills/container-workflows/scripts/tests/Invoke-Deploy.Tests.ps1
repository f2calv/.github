#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    function dotnet-gitversion { }

    $repositoryRoot = Join-Path $TestDrive 'application'
    New-Item -ItemType Directory -Path $repositoryRoot | Out-Null
    . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot
}

Describe 'Invoke-Deploy manifest handling' -Tag 'Unit' {
    It 'selects the Application source path' {
        Get-ManifestSourcePrefix Application | Should -Be '.spec.source'
    }

    It 'selects the ApplicationSet template source path' {
        Get-ManifestSourcePrefix ApplicationSet | Should -Be '.spec.template.spec.source'
    }

    It 'rejects unsupported manifest kinds' {
        { Get-ManifestSourcePrefix Deployment } | Should -Throw '*Application or ApplicationSet*'
    }

    It 'patches targetRevision and shared image and annotation paths' {
        $expression = Get-ManifestPatchExpression ApplicationSet -Chart
        $expression | Should -Match '\.spec\.template\.spec\.source\.targetRevision'
        $expression | Should -Match '_shared\.image\.repository'
        $expression | Should -Match '_shared\.image\.tag'
        $expression | Should -Match '_shared\.podAnnotations'
        $expression | Should -Not -Match '<<'
    }

    It 'leaves YAML merge anchors outside the patch expression' {
        $fixture = "_shared: &shared`n  image: { tag: old }`nworker:`n  <<: *shared`n"
        $fixture | Should -Match '<<: \*shared'
        Get-ManifestPatchExpression ApplicationSet | Should -Not -Match '<<'
    }

    It 'patches a real Application fixture at spec.source' {
        $manifest = Join-Path $TestDrive 'application.yaml'
        Set-Content $manifest @'
kind: Application
spec:
    source:
        targetRevision: old
        helm:
            valuesObject:
                _shared:
                    image:
                        repository: old
                        tag: old
                        pullPolicy: IfNotPresent
                    podAnnotations: {}
'@
        $env:DEPLOY_CHART_VERSION = '1.2.3'
        $env:DEPLOY_IMG_REPO = 'ghcr.io/example/app'
        $env:DEPLOY_IMG_TAG = 'latest-dev'
        $env:DEPLOY_POD_ANNOTATION = 'example.test/deployed-version'
        $env:DEPLOY_STAMP = '1.2.3+stamp'
        yq -i (Get-ManifestPatchExpression Application -Chart) $manifest
        (yq '.spec.source.targetRevision' $manifest) | Should -Be '1.2.3'
        (yq '.spec.source.helm.valuesObject._shared.image.repository' $manifest) | Should -Be 'ghcr.io/example/app'
        (yq '.spec.template' $manifest) | Should -Be 'null'
    }

    It 'patches a real ApplicationSet fixture without changing its merge anchor' {
        $manifest = Join-Path $TestDrive 'application-set.yaml'
        Set-Content $manifest @'
kind: ApplicationSet
spec:
    template:
        spec:
            source:
                targetRevision: old
                helm:
                    valuesObject:
                        _shared: &shared
                            image:
                                repository: old
                                tag: old
                                pullPolicy: IfNotPresent
                            podAnnotations: {}
                        worker:
                            !!merge <<: *shared
'@
        $env:DEPLOY_CHART_VERSION = '1.2.3'
        $env:DEPLOY_IMG_REPO = 'ghcr.io/example/app'
        $env:DEPLOY_IMG_TAG = 'latest-dev'
        $env:DEPLOY_POD_ANNOTATION = 'example.test/deployed-version'
        $env:DEPLOY_STAMP = '1.2.3+stamp'
        yq -i (Get-ManifestPatchExpression ApplicationSet -Chart) $manifest
        (yq '.spec.template.spec.source.targetRevision' $manifest) | Should -Be '1.2.3'
        (Get-Content $manifest -Raw) | Should -Match '<<: \*shared'
    }
}



Describe 'Invoke-Deploy validation and safety' -Tag 'Unit' {
    It 'rejects Release build forwarding' {
        { ConvertTo-DeployBuildArguments @('-Configuration', 'Release') } | Should -Throw '*Debug builds*'
    }

    It 'requires the selected manifest path' {
        { Resolve-DeploymentManifestPath -ManifestPath '' } | Should -Throw '*ManifestPath is required*'
    }

    It 'requires deployment settings before proceeding' {
        { Initialize-DeploymentSettings @{} } | Should -Throw '*PodAnnotationName*'
    }

    It 'returns only the chart object when native commands emit output' {
        Mock Get-Command { [pscustomobject]@{ Name = 'helm' } }
        Mock gh { if ($args -contains 'user') { 'example-user' } else { 'token' } }
        Mock helm { $global:LASTEXITCODE = 0; 'native output' }
        New-Item -ItemType Directory -Path (Join-Path $repositoryRoot 'charts/example') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $repositoryRoot 'charts/example/Chart.yaml') | Out-Null
        $result = @(Publish-ConfiguredDeploymentChart -Root $repositoryRoot -Timestamp '20260923000000' `
                -PublishChart -ApplicationChartPath 'charts/example' `
                -ApplicationChartRepository 'example/charts/example' -Registry 'ghcr.io' `
                -Name 'example' -ImageTag 'latest-dev')
        $result.Count | Should -Be 1
        $result[0].Version | Should -Be '0.0.0-dev.20260923000000'
    }

    It 'retries a push after the upstream advances' {
        $script:pushAttempts = 0
        $script:revisionReads = 0
        Mock git {
            if ($args -contains 'push') {
                $script:pushAttempts++
                $global:LASTEXITCODE = if ($script:pushAttempts -eq 1) { 1 } else { 0 }
                return
            }
            $global:LASTEXITCODE = 0
            if ($args -contains '@{upstream}') { return 'origin/main' }
            if ($args -contains 'fetch') { return }
            if ($args -contains 'rev-parse') {
                $script:revisionReads++
                if ($script:revisionReads -eq 1) { return 'before' }
                return 'after'
            }
        }
        Push-ManifestRepository $repositoryRoot
        $script:pushAttempts | Should -Be 2
    }

    It 'rejects a missing chart before publication' {
        Mock Get-Command { [pscustomobject]@{ Name = 'helm' } }
        { Publish-ConfiguredDeploymentChart -Root $repositoryRoot -Timestamp '20260923000000' `
                -PublishChart -ApplicationChartPath 'charts/missing' `
                -ApplicationChartRepository 'example/charts/missing' -Registry 'ghcr.io' `
                -Name 'example' -ImageTag 'latest-dev' } | Should -Throw '*Chart not found*'
    }

    It 'performs no mutation under WhatIf' {
        Mock Initialize-DeploymentSettings { [pscustomobject]@{ Root = $repositoryRoot; Manifest = 'manifest.yaml'; RelativePath = 'manifest.yaml' } }
        Mock Assert-DeploymentPrerequisites
        Mock Update-ManifestRepository
        Mock Assert-NoModelDrift
        Mock Invoke-DeploymentBuild
        Mock Publish-ConfiguredDeploymentChart
        Mock Update-DeploymentManifest
        Invoke-Deployment -WhatIf
        Should -Invoke Update-ManifestRepository -Times 0
        Should -Invoke Invoke-DeploymentBuild -Times 0
        Should -Invoke Update-DeploymentManifest -Times 0
    }

    It 'loads local settings while preserving explicit values' {
        $configPath = Join-Path $repositoryRoot 'deploy.local.psd1'
        Set-Content $configPath "@{ ManifestRepo = '$repositoryRoot'; ManifestPath = 'app.yaml'; PodAnnotationName = 'example/deployed'; Tag = 'from-config' }"
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot -DeployConfigPath $configPath -Tag 'explicit'
        $deployment = Initialize-DeploymentSettings @{ Tag = 'explicit' }
        $deployment.RelativePath | Should -Be 'app.yaml'
        $Tag | Should -Be 'explicit'
        $PodAnnotationName | Should -Be 'example/deployed'
    }

    It 'updates a clean manifest repository from its upstream' {
        Mock git {
            $global:LASTEXITCODE = 0
            if ($args -contains 'status') { return }
            if ($args -contains '@{upstream}') { return 'origin/main' }
        }
        Update-ManifestRepository $repositoryRoot
        Should -Invoke git -ParameterFilter { $args -contains 'fetch' }
        Should -Invoke git -ParameterFilter { $args -contains 'merge' -and $args -contains 'origin/main' }
    }

    It 'patches and commits an Application manifest' {
        $manifest = Join-Path $repositoryRoot 'app.yaml'
        Set-Content $manifest 'kind: Application'
        $deployment = [pscustomobject]@{ Root = $repositoryRoot; Manifest = $manifest; RelativePath = 'app.yaml' }
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot `
            -ManifestRepo $repositoryRoot -ImageRepository 'ghcr.io/example/app' `
            -Tag 'latest-dev' -PodAnnotationName 'example/deployed' -DeploymentName 'example'
        Mock yq { $global:LASTEXITCODE = 0; if ($args -contains '.kind') { 'Application' } }
        Mock Get-DeploymentGitVersion { '1.2.3' }
        Mock git { $global:LASTEXITCODE = if ($args -contains '--quiet') { 1 } else { 0 } }
        Mock Push-ManifestRepository
        Update-DeploymentManifest $deployment $null '20260923000000'
        Should -Invoke yq -ParameterFilter { $args -contains '-i' }
        Should -Invoke Push-ManifestRepository -Times 1
    }

    It 'coordinates a full deployment and cleanup' {
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot -ManifestRepo $repositoryRoot
        Mock Initialize-DeploymentSettings { [pscustomobject]@{ Root = $repositoryRoot; Manifest = 'manifest.yaml'; RelativePath = 'manifest.yaml' } }
        Mock Assert-DeploymentPrerequisites
        Mock Update-ManifestRepository
        Mock Assert-NoModelDrift
        Mock Invoke-DeploymentBuild
        Mock Publish-ConfiguredDeploymentChart { $null }
        Mock Update-DeploymentManifest
        Invoke-Deployment
        Should -Invoke Update-ManifestRepository -Times 1
        Should -Invoke Invoke-DeploymentBuild -Times 1
        Should -Invoke Update-DeploymentManifest -Times 1
    }

    It 'commits the patched manifest with the chart version' {
        $gitRoot = Join-Path $TestDrive 'publish-repository'
        New-Item -ItemType Directory -Path $gitRoot | Out-Null
        git -C $gitRoot init --initial-branch main | Out-Null
        git -C $gitRoot config user.name 'Example User'
        git -C $gitRoot config user.email 'user@example.com'
        $manifest = Join-Path $gitRoot 'application.yaml'
        Set-Content $manifest "kind: Application`nspec:`n  source:`n    targetRevision: old"
        git -C $gitRoot add -- application.yaml
        git -C $gitRoot commit -m 'initial' | Out-Null
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot `
            -ManifestRepo $gitRoot -DeploymentName 'example' -Tag 'latest-dev' -Chart `
            -ImageRepository 'ghcr.io/example/app' -PodAnnotationName 'example/deployed'
        $deployment = [pscustomobject]@{ Root = $repositoryRoot; Manifest = $manifest; RelativePath = 'application.yaml' }
        Mock Get-DeploymentGitVersion { '1.2.3' }
        Mock Push-ManifestRepository
        Update-DeploymentManifest $deployment ([pscustomobject]@{ Version = '2.0.0' }) '20260927000000'
        @(git -C $gitRoot diff-tree --no-commit-id --name-only -r HEAD) | Should -Be @('application.yaml')
        "$(git -C $gitRoot log -1 --format='%s')" | Should -Match 'chart=2\.0\.0$'
        (yq '.spec.source.targetRevision' $manifest) | Should -Be '2.0.0'
        Should -Invoke Push-ManifestRepository -Times 1
    }

    It 'validates an existing manifest when yq is available' {
        $manifest = Join-Path $repositoryRoot 'valid.yaml'
        Set-Content $manifest 'kind: Application'
        Mock Get-Command { [pscustomobject]@{ Name = 'yq' } }
        { Assert-DeploymentPrerequisites $manifest } | Should -Not -Throw
    }

    It 'resolves the deployment version with an installed GitVersion tool' {
        Mock Get-Command { [pscustomobject]@{ Name = 'dotnet-gitversion' } }
        Mock dotnet-gitversion { '1.2.3' }
        Get-DeploymentGitVersion $repositoryRoot | Should -Be '1.2.3'
    }

    It 'runs the configured EF model-drift check and restores environment state' {
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot `
            -MigrationProject 'src/Data.csproj' -MigrationContext 'DataContext' `
            -MigrationConnectionStringEnvironmentVariable 'TEST_DB' -MigrationConnectionString 'synthetic'
        Mock Get-Command { [pscustomobject]@{ Name = 'dotnet' } }
        Mock dotnet { $global:LASTEXITCODE = 0 }
        Assert-NoModelDrift $repositoryRoot
        Should -Invoke dotnet -ParameterFilter { $args -contains 'has-pending-model-changes' -and $args -contains 'DataContext' }
        [Environment]::GetEnvironmentVariable('TEST_DB') | Should -BeNullOrEmpty
    }

    It 'invokes the repository build shim for an image deployment' {
        $buildScript = Join-Path $repositoryRoot 'build.ps1'
        Set-Content $buildScript "param([switch]`$Push, [string]`$Configuration, [string]`$Platforms, [string]`$Tag); exit 0"
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot `
            -Platforms 'linux/amd64' -Tag 'test'
        Invoke-DeploymentBuild $repositoryRoot
    }

    It 'returns without committing when the manifest has no diff' {
        $manifest = Join-Path $repositoryRoot 'unchanged.yaml'
        Set-Content $manifest 'kind: ApplicationSet'
        $deployment = [pscustomobject]@{ Root = $repositoryRoot; Manifest = $manifest; RelativePath = 'unchanged.yaml' }
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot `
            -ManifestRepo $repositoryRoot -ImageRepository 'ghcr.io/example/app' `
            -Tag 'latest-dev' -PodAnnotationName 'example/deployed' -DeploymentName 'example'
        Mock yq { $global:LASTEXITCODE = 0; if ($args -contains '.kind') { 'ApplicationSet' } }
        Mock Get-DeploymentGitVersion { '1.2.3' }
        Mock git { $global:LASTEXITCODE = 0 }
        Mock Push-ManifestRepository
        Update-DeploymentManifest $deployment $null '20260923000000'
        Should -Invoke Push-ManifestRepository -Times 0
    }
}
