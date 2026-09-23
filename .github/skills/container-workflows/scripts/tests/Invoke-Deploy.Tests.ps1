#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    $repositoryRoot = Join-Path $TestDrive 'application'
    New-Item -ItemType Directory -Path $repositoryRoot | Out-Null
    . (Join-Path $PSScriptRoot '../Invoke-Deploy.ps1') -RepositoryRoot $repositoryRoot
}

Describe 'Invoke-Deploy manifest handling' {
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
}


Describe 'Invoke-Deploy validation and safety' {
    It 'rejects Release build forwarding' {
        { ConvertTo-DeployBuildArguments @('-Configuration', 'Release') } | Should -Throw '*Debug builds*'
    }

    It 'requires the selected manifest path' {
        { Resolve-DeploymentManifestPath -OnlyCharts -ManifestPath app.yaml } | Should -Throw '*DashboardManifestPath*'
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
        $script:DeployConfigPath = $configPath
        $script:Tag = 'explicit'
        $deployment = Initialize-DeploymentSettings @{ Tag = 'explicit' }
        $deployment.RelativePath | Should -Be 'app.yaml'
        $script:Tag | Should -Be 'explicit'
        $script:PodAnnotationName | Should -Be 'example/deployed'
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
        $script:OnlyCharts = $true
        Invoke-DeploymentBuild $repositoryRoot
        $script:OnlyCharts = $false
    }

    It 'patches and commits an Application manifest' {
        $manifest = Join-Path $repositoryRoot 'app.yaml'
        Set-Content $manifest 'kind: Application'
        $deployment = [pscustomobject]@{ Root = $repositoryRoot; Manifest = $manifest; RelativePath = 'app.yaml' }
        $script:ManifestRepo = $repositoryRoot
        $script:ImageRepository = 'ghcr.io/example/app'
        $script:Tag = 'latest-dev'
        $script:PodAnnotationName = 'example/deployed'
        $script:DeploymentName = 'example'
        $script:NoCommit = $false
        $script:OnlyCharts = $false
        $script:Chart = $false
        Mock yq { $global:LASTEXITCODE = 0; if ($args -contains '.kind') { 'Application' } }
        Mock Get-DeploymentGitVersion { '1.2.3' }
        Mock git { $global:LASTEXITCODE = if ($args -contains '--quiet') { 1 } else { 0 } }
        Mock Push-ManifestRepository
        Update-DeploymentManifest $deployment $null '20260923000000'
        Should -Invoke yq -ParameterFilter { $args -contains '-i' }
        Should -Invoke Push-ManifestRepository -Times 1
    }

    It 'coordinates a full deployment and cleanup' {
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
}