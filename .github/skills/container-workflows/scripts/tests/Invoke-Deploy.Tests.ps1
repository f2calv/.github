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
        { Resolve-DeploymentManifestPath -OnlyCharts -ManifestPath app.yaml } | Should -Throw '*DashboardManifestPath*'
    }

    It 'accepts an explicit charts-only manifest without an application manifest' {
        $chartsOnlyRoot = Join-Path $TestDrive 'charts-only'
        New-Item -ItemType Directory -Path $chartsOnlyRoot | Out-Null
        $manifest = Join-Path $chartsOnlyRoot 'dashboard-only.yaml'
        Set-Content $manifest "kind: Application`nspec:`n  source:`n    repoURL: ghcr.io/example`n    chart: charts/example-dashboards"
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $chartsOnlyRoot `
            -OnlyCharts -ManifestRepo $chartsOnlyRoot -DashboardManifestPath 'dashboard-only.yaml'
        $deployment = Initialize-DeploymentSettings @{
            OnlyCharts = $true
            ManifestRepo = $chartsOnlyRoot
            DashboardManifestPath = 'dashboard-only.yaml'
        }
        $deployment.RelativePath | Should -Be 'dashboard-only.yaml'
    }

    It 'requires deployment settings before proceeding' {
        { Initialize-DeploymentSettings @{} } | Should -Throw '*PodAnnotationName*'
    }

    It 'rejects conflicting dashboard modes' {
        { Assert-DashboardMode -OnlyCharts -SkipDashboards } | Should -Throw '*cannot be used together*'
    }

    It 'discovers a dashboard chart and Application manifest from the application source' {
        $chartDirectory = Join-Path $repositoryRoot 'charts/example-dashboards'
        New-Item -ItemType Directory -Path $chartDirectory -Force | Out-Null
        Set-Content (Join-Path $chartDirectory 'Chart.yaml') "apiVersion: v2`nname: example-dashboards`nversion: 1.0.0"
        $applicationManifest = Join-Path $repositoryRoot 'application.yaml'
        Set-Content $applicationManifest "kind: Application`nspec:`n  source:`n    repoURL: ghcr.io/example`n    chart: charts/example"
        $dashboardManifest = Join-Path $repositoryRoot 'dashboard.yaml'
        Set-Content $dashboardManifest "kind: Application`nspec:`n  source:`n    repoURL: ghcr.io/example`n    chart: charts/example-dashboards"
        $result = Resolve-DashboardDeployment -Root $repositoryRoot -Repository $repositoryRoot `
            -ApplicationManifest $applicationManifest -Registry 'ghcr.io'
        $result.ChartPath | Should -Be 'charts/example-dashboards'
        $result.RelativePath | Should -Be 'dashboard.yaml'
        $result.ChartRepository | Should -Be 'example/charts/example-dashboards'
    }

    It 'discovers a dashboard chart and ApplicationSet manifest from the application source' {
        $root = Join-Path $TestDrive 'application-set-discovery'
        $chartDirectory = Join-Path $root 'charts/dashboards'
        New-Item -ItemType Directory -Path $chartDirectory -Force | Out-Null
        Set-Content (Join-Path $chartDirectory 'Chart.yaml') "apiVersion: v2`nname: dashboards`nversion: 1.0.0"
        $applicationManifest = Join-Path $root 'application.yaml'
        Set-Content $applicationManifest "kind: ApplicationSet`nspec:`n  template:`n    spec:`n      source:`n        repoURL: ghcr.io/example`n        chart: app/charts/application"
        $dashboardManifest = Join-Path $root 'dashboard.yaml'
        Set-Content $dashboardManifest "kind: ApplicationSet`nspec:`n  template:`n    spec:`n      source:`n        repoURL: ghcr.io/example`n        chart: app/charts/dashboards"
        $result = Resolve-DashboardDeployment -Root $root -Repository $root `
            -ApplicationManifest $applicationManifest -Registry 'ghcr.io'
        $result.ChartRepository | Should -Be 'example/app/charts/dashboards'
        $result.ChartName | Should -Be 'dashboards'
    }

    It 'skips dashboard discovery when explicitly disabled' {
        Resolve-DashboardDeployment -Root $repositoryRoot -Repository $repositoryRoot `
            -ApplicationManifest 'unused.yaml' -Registry 'ghcr.io' -Skip | Should -BeNullOrEmpty
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
        Mock Resolve-DashboardDeployment { $null }
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

    It 'skips image builds for charts-only deployment' {
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot -OnlyCharts
        Invoke-DeploymentBuild $repositoryRoot
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
        Mock Resolve-DashboardDeployment { $null }
        Mock Assert-DeploymentPrerequisites
        Mock Update-ManifestRepository
        Mock Assert-NoModelDrift
        Mock Invoke-DeploymentBuild
        Mock Publish-ConfiguredDeploymentChart { $null }
        Mock Update-DeploymentManifest
        Mock Publish-DeploymentChanges
        Invoke-Deployment -CallerBoundParameters @{ OnlyCharts = $false; SkipDashboards = $false }
        Should -Invoke Update-ManifestRepository -Times 1
        Should -Invoke Invoke-DeploymentBuild -Times 1
        Should -Invoke Update-DeploymentManifest -Times 1
    }

    It 'publishes and patches a discovered dashboard during a normal deployment' {
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot -ManifestRepo $repositoryRoot
        $application = [pscustomobject]@{ Root = $repositoryRoot; Manifest = 'application.yaml'; RelativePath = 'application.yaml' }
        $dashboard = [pscustomobject]@{
            Root = $repositoryRoot
            Manifest = 'dashboard.yaml'
            RelativePath = 'dashboard.yaml'
            ChartPath = 'charts/example-dashboards'
            ChartRepository = 'example/charts/example-dashboards'
            ChartName = 'example-dashboards'
        }
        Mock Initialize-DeploymentSettings { $application }
        Mock Resolve-DashboardDeployment { $dashboard }
        Mock Assert-DeploymentPrerequisites
        Mock Update-ManifestRepository
        Mock Assert-NoModelDrift
        Mock Invoke-DeploymentBuild
        Mock Publish-ConfiguredDeploymentChart {
            if ($PublishOnlyCharts) { return [pscustomobject]@{ Version = '0.0.0-dev.1' } }
            return $null
        }
        Mock Update-DeploymentManifest
        Mock Publish-DeploymentChanges
        Invoke-Deployment -CallerBoundParameters @{ OnlyCharts = $false; SkipDashboards = $false }
        Should -Invoke Publish-ConfiguredDeploymentChart -Times 1 -ParameterFilter { $PublishOnlyCharts }
        Should -Invoke Update-DeploymentManifest -Times 1 -ParameterFilter { $Dashboard }
        Should -Invoke Update-DeploymentManifest -Times 1 -ParameterFilter { -not $Dashboard.IsPresent }
        Should -Invoke Publish-DeploymentChanges -Times 1 -ParameterFilter {
            $Deployments.Count -eq 2 -and $DashboardChart.Version -eq '0.0.0-dev.1'
        }
    }

    It 'restores both manifests and does not commit when the dashboard patch fails' {
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot -ManifestRepo $repositoryRoot
        $application = [pscustomobject]@{ Root = $repositoryRoot; Manifest = 'application.yaml'; RelativePath = 'application.yaml' }
        $dashboard = [pscustomobject]@{
            Root = $repositoryRoot
            Manifest = 'dashboard.yaml'
            RelativePath = 'dashboard.yaml'
            ChartPath = 'charts/example-dashboards'
            ChartRepository = 'example/charts/example-dashboards'
            ChartName = 'example-dashboards'
        }
        $script:updateCalls = 0
        Mock Initialize-DeploymentSettings { $application }
        Mock Resolve-DashboardDeployment { $dashboard }
        Mock Assert-DeploymentPrerequisites
        Mock Update-ManifestRepository
        Mock Assert-NoModelDrift
        Mock Invoke-DeploymentBuild
        Mock Publish-ConfiguredDeploymentChart { [pscustomobject]@{ Version = '0.0.0-dev.1' } }
        Mock Update-DeploymentManifest {
            $script:updateCalls++
            if ($script:updateCalls -eq 2) { throw 'dashboard patch failed' }
        }
        Mock Publish-DeploymentChanges
        Mock Restore-DeploymentManifests
        { Invoke-Deployment -CallerBoundParameters @{ OnlyCharts = $false; SkipDashboards = $false } } |
            Should -Throw '*dashboard patch failed*'
        Should -Invoke Publish-DeploymentChanges -Times 0
        Should -Invoke Restore-DeploymentManifests -Times 1 -ParameterFilter {
            $Deployments.Count -eq 2 -and
            $Deployments.RelativePath -contains 'application.yaml' -and
            $Deployments.RelativePath -contains 'dashboard.yaml'
        }
    }

    It 'restores every partially patched manifest' {
        $gitRoot = Join-Path $TestDrive 'restore-repository'
        New-Item -ItemType Directory -Path $gitRoot | Out-Null
        git -C $gitRoot init --initial-branch main | Out-Null
        git -C $gitRoot config user.name 'Example User'
        git -C $gitRoot config user.email 'user@example.com'
        Set-Content (Join-Path $gitRoot 'application.yaml') 'original application'
        Set-Content (Join-Path $gitRoot 'dashboard.yaml') 'original dashboard'
        git -C $gitRoot add -- application.yaml dashboard.yaml
        git -C $gitRoot commit -m 'initial' | Out-Null
        Set-Content (Join-Path $gitRoot 'application.yaml') 'changed application'
        Set-Content (Join-Path $gitRoot 'dashboard.yaml') 'changed dashboard'
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot -ManifestRepo $gitRoot
        $deployments = @(
            [pscustomobject]@{ RelativePath = 'application.yaml' },
            [pscustomobject]@{ RelativePath = 'dashboard.yaml' }
        )
        Restore-DeploymentManifests -Deployments $deployments
        (Get-Content (Join-Path $gitRoot 'application.yaml') -Raw).Trim() | Should -Be 'original application'
        (Get-Content (Join-Path $gitRoot 'dashboard.yaml') -Raw).Trim() | Should -Be 'original dashboard'
    }

    It 'commits application and dashboard changes together' {
        $gitRoot = Join-Path $TestDrive 'publish-repository'
        New-Item -ItemType Directory -Path $gitRoot | Out-Null
        git -C $gitRoot init --initial-branch main | Out-Null
        git -C $gitRoot config user.name 'Example User'
        git -C $gitRoot config user.email 'user@example.com'
        Set-Content (Join-Path $gitRoot 'application.yaml') 'original application'
        Set-Content (Join-Path $gitRoot 'dashboard.yaml') 'original dashboard'
        git -C $gitRoot add -- application.yaml dashboard.yaml
        git -C $gitRoot commit -m 'initial' | Out-Null
        Set-Content (Join-Path $gitRoot 'application.yaml') 'changed application'
        Set-Content (Join-Path $gitRoot 'dashboard.yaml') 'changed dashboard'
        . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot `
            -ManifestRepo $gitRoot -DeploymentName 'example' -Tag 'latest-dev'
        $deployments = @(
            [pscustomobject]@{ RelativePath = 'application.yaml' },
            [pscustomobject]@{ RelativePath = 'dashboard.yaml' }
        )
        $env:DEPLOY_STAMP = '1.2.3+stamp'
        Mock Push-ManifestRepository
        Publish-DeploymentChanges -Deployments $deployments `
            -ApplicationChart ([pscustomobject]@{ Version = '2.0.0' }) `
            -DashboardChart ([pscustomobject]@{ Version = '3.0.0' }) `
            -Timestamp '20260927000000'
        @(git -C $gitRoot diff-tree --no-commit-id --name-only -r HEAD) | Should -Be @('application.yaml', 'dashboard.yaml')
        "$(git -C $gitRoot log -1 --format='%s')" | Should -Match 'chart=2.0.0 dashboards=3.0.0'
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

    It 'validates and publishes a dashboards chart' {
        $chartRoot = Join-Path $repositoryRoot 'charts/dashboards'
        New-Item -ItemType Directory -Path (Join-Path $chartRoot 'dashboards') -Force | Out-Null
        Set-Content (Join-Path $chartRoot 'Chart.yaml') 'apiVersion: v2'
        Set-Content (Join-Path $chartRoot 'dashboards/example.json') '{}'
        Mock Get-Command { [pscustomobject]@{ Name = 'helm' } }
        Mock gh { $global:LASTEXITCODE = 0; if ($args -contains 'user') { 'example-user' } else { 'token' } }
        Mock helm { $global:LASTEXITCODE = 0; 'native output' }
        $result = Publish-ConfiguredDeploymentChart -Root $repositoryRoot -Timestamp '20260923000000' `
            -PublishOnlyCharts -DashboardsChartPath 'charts/dashboards' `
            -DashboardsChartRepository 'example/charts/dashboards' -Registry 'ghcr.io' `
            -Name 'example' -ImageTag 'latest-dev'
        $result.Version | Should -Be '0.0.0-dev.20260923000000'
        Should -Invoke helm -ParameterFilter { $args -contains 'lint' }
        Should -Invoke helm -ParameterFilter { $args -contains 'template' }
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
