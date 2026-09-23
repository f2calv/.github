#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Builds and deploys an application through a caller-supplied GitOps repository.
.DESCRIPTION
    Publishes a Debug image and optional Helm chart, then patches an Argo CD Application or
    ApplicationSet. Defaults come from the caller's gitignored deploy.local.psd1.
.PARAMETER RepositoryRoot
    Root directory of the calling application repository.
.EXAMPLE
    ./Invoke-Deploy.ps1 -RepositoryRoot /src/example -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })][string]$RepositoryRoot,
    [string]$Tag = 'latest-dev', [string]$Platforms = 'linux/arm64', [string]$DeployConfigPath,
    [string]$ManifestRepo, [string]$ManifestPath, [string]$ImageRepository,
    [switch]$SkipBuild, [switch]$NoCommit, [switch]$SkipMigrationCheck, [switch]$Chart,
    [Alias('OnlyDashboards')][switch]$OnlyCharts,
    [string]$ChartPath, [string]$ChartRegistry = 'ghcr.io', [string]$ChartRepository,
    [string]$DashboardChartPath, [string]$DashboardChartRepository, [string]$DashboardManifestPath,
    [string]$ChartVersion, [string]$DeploymentName, [string]$PodAnnotationName,
    [string]$MigrationProject, [string]$MigrationContext,
    [string]$MigrationConnectionStringEnvironmentVariable, [string]$MigrationConnectionString,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

#region Pure functions
function ConvertTo-DeployBuildArguments {
    [CmdletBinding()][OutputType([string[]])]
    param([AllowEmptyCollection()][string[]]$Arguments)
    $result = [Collections.Generic.List[string]]::new()
    $items = @($Arguments | Where-Object { $null -ne $_ })
    for ($index = 0; $index -lt $items.Count; $index++) {
        if ($items[$index] -match '^-Configuration(?::(.+))?$') {
            $value = if ($Matches[1]) { $Matches[1] } elseif ($index + 1 -lt $items.Count) { $items[++$index] } else { 'Debug' }
            if ($value -ne 'Debug') { throw "Deployment only performs Debug builds; '-Configuration $value' is not supported." }
            continue
        }
        $result.Add($items[$index])
    }
    return $result.ToArray()
}

function Resolve-DeploymentManifestPath {
    [CmdletBinding()][OutputType([string])]
    param([switch]$OnlyCharts, [string]$ManifestPath, [string]$DashboardManifestPath)
    $path = if ($OnlyCharts) { $DashboardManifestPath } else { $ManifestPath }
    if ([string]::IsNullOrWhiteSpace($path)) {
        $name = if ($OnlyCharts) { 'DashboardManifestPath' } else { 'ManifestPath' }
        throw "-$name is required for this deployment mode."
    }
    return $path
}

function Get-ManifestSourcePrefix {
    [CmdletBinding()][OutputType([string])]
    param([Parameter(Mandatory)][string]$Kind)
    switch ($Kind) {
        'Application' { return '.spec.source' }
        'ApplicationSet' { return '.spec.template.spec.source' }
        default { throw "Unsupported Argo CD manifest kind '$Kind'. Expected Application or ApplicationSet." }
    }
}

function Get-ManifestPatchExpression {
    [CmdletBinding()][OutputType([string])]
    param([Parameter(Mandatory)][string]$Kind, [switch]$Chart, [switch]$OnlyCharts)
    $source = Get-ManifestSourcePrefix -Kind $Kind
    if ($OnlyCharts) { return "$source.targetRevision = strenv(DEPLOY_CHART_VERSION)" }
    $parts = [Collections.Generic.List[string]]::new()
    if ($Chart) { $parts.Add("$source.targetRevision = strenv(DEPLOY_CHART_VERSION)") }
    $parts.Add("$source.helm.valuesObject._shared.image.repository = strenv(DEPLOY_IMG_REPO)")
    $parts.Add("$source.helm.valuesObject._shared.image.tag = strenv(DEPLOY_IMG_TAG)")
    $parts.Add("$source.helm.valuesObject._shared.image.pullPolicy = `"Always`"")
    $parts.Add("$source.helm.valuesObject._shared.podAnnotations[strenv(DEPLOY_POD_ANNOTATION)] = strenv(DEPLOY_STAMP)")
    $parts.Add("($source.helm.valuesObject[] | select(has(`"podAnnotations`"))).podAnnotations[strenv(DEPLOY_POD_ANNOTATION)] = strenv(DEPLOY_STAMP)")
    return $parts -join ' | '
}
#endregion Pure functions

#region Settings and prerequisites
function Initialize-DeploymentSettings {
    [CmdletBinding()][OutputType([pscustomobject])]
    param([Parameter(Mandatory)][hashtable]$CallerBoundParameters)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    if (-not $DeployConfigPath) { $script:DeployConfigPath = Join-Path $root 'deploy.local.psd1' }
    foreach ($item in $CallerBoundParameters.GetEnumerator()) { Set-Variable $item.Key $item.Value -Scope 1 -WhatIf:$false }
    if (Test-Path -LiteralPath $DeployConfigPath) {
        foreach ($item in (Import-PowerShellDataFile $DeployConfigPath).GetEnumerator()) {
            if (-not $CallerBoundParameters.ContainsKey($item.Key)) { Set-Variable $item.Key $item.Value -Scope 1 -WhatIf:$false }
        }
    }
    $name = Split-Path $root -Leaf
    if (-not $DeploymentName) { Set-Variable DeploymentName $name.ToLowerInvariant() -Scope 1 -WhatIf:$false }
    if (-not $ImageRepository) { Set-Variable ImageRepository "ghcr.io/f2calv/$($name.ToLowerInvariant())" -Scope 1 -WhatIf:$false }
    if (-not $OnlyCharts -and -not $PodAnnotationName) { throw "-PodAnnotationName is required. Supply it explicitly or in '$DeployConfigPath'." }
    if (-not $ManifestRepo) { throw "-ManifestRepo is required. Supply it explicitly or in '$DeployConfigPath'." }
    $script:Rest = @(ConvertTo-DeployBuildArguments $Rest)
    $relative = Resolve-DeploymentManifestPath -OnlyCharts:$OnlyCharts -ManifestPath $ManifestPath -DashboardManifestPath $DashboardManifestPath
    return [pscustomobject]@{ Root = $root; RelativePath = $relative; Manifest = Join-Path $ManifestRepo $relative }
}

function Assert-DeploymentPrerequisites {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Manifest)
    if (-not (Get-Command yq -ErrorAction SilentlyContinue)) { throw 'yq not found. Install MikeFarah.yq to patch the manifest.' }
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "GitOps manifest not found at '$Manifest'." }
}

function Update-ManifestRepository {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository)
    if (@(git -C $Repository status --porcelain).Count -gt 0) { throw "GitOps repository '$Repository' has local changes." }
    git -C $Repository fetch --prune
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed for '$Repository'." }
    $upstream = "$(git -C $Repository rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')".Trim()
    if ($LASTEXITCODE -ne 0 -or -not $upstream) { throw 'The current GitOps branch has no upstream branch.' }
    git -C $Repository merge --ff-only $upstream
    if ($LASTEXITCODE -ne 0) { throw "GitOps branch could not be fast-forwarded to '$upstream'." }
}

function Push-ManifestRepository {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        git -C $Repository push
        if ($LASTEXITCODE -eq 0) { return }
        if ($attempt -eq 3) { throw 'git push failed after 3 attempts.' }
        $upstream = "$(git -C $Repository rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')".Trim()
        $before = "$(git -C $Repository rev-parse $upstream)".Trim()
        git -C $Repository fetch --prune
        if ($LASTEXITCODE -ne 0) { throw 'git push failed and the GitOps repository could not be refreshed.' }
        $after = "$(git -C $Repository rev-parse $upstream)".Trim()
        if ($before -eq $after) { throw 'git push failed without the upstream advancing.' }
        git -C $Repository rebase $upstream
        if ($LASTEXITCODE -ne 0) {
            git -C $Repository rebase --abort
            throw 'Automatic GitOps rebase failed and was aborted.'
        }
    }
}
#endregion Settings and prerequisites

#region Build and chart
function Assert-NoModelDrift {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    if ($SkipMigrationCheck -or $OnlyCharts -or -not $MigrationProject) { return }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'dotnet not found for the EF model-drift check.' }
    $project = Join-Path $Root $MigrationProject
    $previous = if ($MigrationConnectionStringEnvironmentVariable) { [Environment]::GetEnvironmentVariable($MigrationConnectionStringEnvironmentVariable) }
    $previousArtifactsPath = $env:ArtifactsPath
    $previousBaseOutputPath = $env:BaseOutputPath
    $temporaryOutput = Join-Path ([IO.Path]::GetTempPath()) "ef-output-$PID-$([Guid]::NewGuid().ToString('N'))"
    try {
        $env:ArtifactsPath = $null
        $env:BaseOutputPath = Join-Path $temporaryOutput 'bin/'
        if ($MigrationConnectionStringEnvironmentVariable) { [Environment]::SetEnvironmentVariable($MigrationConnectionStringEnvironmentVariable, $MigrationConnectionString) }
        dotnet tool restore | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'dotnet tool restore failed.' }
        dotnet restore $project | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed for the EF model-drift check.' }
        $arguments = @('ef', 'migrations', 'has-pending-model-changes', '--project', $project, '--startup-project', $project)
        if ($MigrationContext) { $arguments += @('--context', $MigrationContext) }
        dotnet @arguments
        if ($LASTEXITCODE -ne 0) { throw 'EF model/migration drift check failed.' }
    }
    finally {
        $env:ArtifactsPath = $previousArtifactsPath
        $env:BaseOutputPath = $previousBaseOutputPath
        if ($MigrationConnectionStringEnvironmentVariable) { [Environment]::SetEnvironmentVariable($MigrationConnectionStringEnvironmentVariable, $previous) }
        Remove-Item $temporaryOutput -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-DeploymentBuild {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    if ($OnlyCharts) { Write-Host 'Skipping image build/push (-OnlyCharts).' -ForegroundColor Yellow; return }
    if ($SkipBuild) { Write-Host "Skipping build/push (-SkipBuild); re-rolling ${ImageRepository}:${Tag}" -ForegroundColor Yellow; return }
    & (Join-Path $Root 'build.ps1') -Push -Configuration Debug -Platforms $Platforms -Tag $Tag @Rest
    if ($LASTEXITCODE -ne 0) { throw "build.ps1 failed with exit code $LASTEXITCODE." }
}

function Publish-ConfiguredDeploymentChart {
    [CmdletBinding()][OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Timestamp,
        [switch]$PublishChart,
        [switch]$PublishOnlyCharts,
        [string]$ApplicationChartPath,
        [string]$ApplicationChartRepository,
        [string]$DashboardsChartPath,
        [string]$DashboardsChartRepository,
        [string]$RequestedChartVersion,
        [string]$Registry,
        [string]$Name,
        [string]$ImageTag
    )
    if (-not $PublishChart -and -not $PublishOnlyCharts) { return $null }
    if (-not (Get-Command helm -ErrorAction SilentlyContinue)) { throw 'helm not found. Install Helm to publish charts.' }
    $path = if ($PublishOnlyCharts) { $DashboardsChartPath } else { $ApplicationChartPath }
    $repository = if ($PublishOnlyCharts) { $DashboardsChartRepository } else { $ApplicationChartRepository }
    if (-not $path -or -not $repository) { throw 'ChartPath and ChartRepository are required for chart deployment.' }
    $version = if ($RequestedChartVersion) { $RequestedChartVersion } else { "0.0.0-dev.$Timestamp" }
    $directory = Join-Path $Root $path
    if (-not (Test-Path (Join-Path $directory 'Chart.yaml') -PathType Leaf)) { throw "Chart not found at '$directory'." }
    $chartObject = [pscustomobject]@{ Path = $path; Repository = $repository; Version = $version; Directory = $directory; Name = Split-Path $path -Leaf }
    if ($PublishOnlyCharts) {
        Get-ChildItem (Join-Path $directory 'dashboards/*.json') | ForEach-Object {
            try { $null = Get-Content $_.FullName -Raw | ConvertFrom-Json }
            catch { throw "Invalid dashboard JSON '$($_.FullName)': $($_.Exception.Message)" }
        }
        helm lint $directory | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'helm lint failed.' }
        helm template $chartObject.Name $directory | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'helm template failed.' }
    }
    $user = "$(gh api user --jq .login)".Trim()
    gh auth token | helm registry login $Registry --username $user --password-stdin | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'helm registry login failed.' }
    $packageDirectory = Join-Path ([IO.Path]::GetTempPath()) "$Name-chart-$Timestamp"
    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
    try {
        helm dependency update $directory | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'helm dependency update failed.' }
        $appVersion = if ($PublishOnlyCharts) { $version } else { $ImageTag }
        helm package $directory --version $version --app-version $appVersion --destination $packageDirectory | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'helm package failed.' }
        $package = Join-Path $packageDirectory "$($chartObject.Name)-$version.tgz"
        $target = "oci://$Registry/$($repository -replace '/[^/]+$', '')"
        helm push $package $target | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'helm push failed.' }
    }
    finally { Remove-Item $packageDirectory -Recurse -Force -ErrorAction SilentlyContinue }
    return $chartObject
}
#endregion Build and chart

#region Manifest update
function Get-DeploymentGitVersion {
    [CmdletBinding()][OutputType([string])]
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Get-Command dotnet-gitversion -ErrorAction SilentlyContinue)) {
        dotnet tool install -g GitVersion.Tool | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Failed to install GitVersion.Tool.' }
        $toolsPath = Join-Path $HOME '.dotnet/tools'
        if ($env:PATH -notlike "*$toolsPath*") { $env:PATH = "$toolsPath$([IO.Path]::PathSeparator)$env:PATH" }
    }
    return "$(dotnet-gitversion $Root /showvariable FullSemVer)".Trim()
}

function Update-DeploymentManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Deployment, [pscustomobject]$DeploymentChart, [Parameter(Mandatory)][string]$Timestamp)
    $kind = "$(yq '.kind' $Deployment.Manifest)".Trim()
    if ($LASTEXITCODE -ne 0) { throw 'yq failed to read the manifest kind.' }
    $env:DEPLOY_CHART_VERSION = if ($DeploymentChart) { $DeploymentChart.Version } else { '' }
    $env:DEPLOY_IMG_REPO = $ImageRepository
    $env:DEPLOY_IMG_TAG = $Tag
    $env:DEPLOY_POD_ANNOTATION = $PodAnnotationName
    $env:DEPLOY_STAMP = "$(Get-DeploymentGitVersion $Deployment.Root)+$Timestamp"
    $expression = Get-ManifestPatchExpression -Kind $kind -Chart:$Chart -OnlyCharts:$OnlyCharts
    yq -i $expression $Deployment.Manifest
    if ($LASTEXITCODE -ne 0) { throw 'yq failed to patch the manifest.' }
    git -C $ManifestRepo diff --quiet -- $Deployment.RelativePath
    if ($LASTEXITCODE -eq 0) { Write-Host 'No GitOps changes detected.' -ForegroundColor Yellow; return }
    if ($NoCommit) { Write-Host 'GitOps manifest patched but not committed (-NoCommit).' -ForegroundColor Yellow; return }
    git -C $ManifestRepo add -- $Deployment.RelativePath
    $message = if ($OnlyCharts) { "deploy($DeploymentName-dashboards): chart=$($DeploymentChart.Version)" } else { "deploy($DeploymentName): $Tag $($env:DEPLOY_STAMP)" }
    git -C $ManifestRepo commit -m $message
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
    Push-ManifestRepository $ManifestRepo
}
#endregion Manifest update

#region Main execution
function Invoke-Deployment {
    [CmdletBinding(SupportsShouldProcess)]
    param([hashtable]$CallerBoundParameters = @{})
    $deployment = Initialize-DeploymentSettings $CallerBoundParameters
    Assert-DeploymentPrerequisites $deployment.Manifest
    if (-not $PSCmdlet.ShouldProcess($deployment.Manifest, 'Build and deploy artifacts, then patch the GitOps manifest')) { return }
    try {
        Update-ManifestRepository $ManifestRepo
        $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
        Assert-NoModelDrift $deployment.Root
        Invoke-DeploymentBuild $deployment.Root
        $deploymentChart = Publish-ConfiguredDeploymentChart -Root $deployment.Root -Timestamp $timestamp `
            -PublishChart:$Chart -PublishOnlyCharts:$OnlyCharts -ApplicationChartPath $ChartPath `
            -ApplicationChartRepository $ChartRepository -DashboardsChartPath $DashboardChartPath `
            -DashboardsChartRepository $DashboardChartRepository -RequestedChartVersion $ChartVersion `
            -Registry $ChartRegistry -Name $DeploymentName -ImageTag $Tag
        Update-DeploymentManifest $deployment $deploymentChart $timestamp
    }
    finally {
        $dependencies = Join-Path $deployment.Root 'deps'
        if (Test-Path $dependencies) { Remove-Item $dependencies -Recurse -Force }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-Deployment -CallerBoundParameters $PSBoundParameters -WhatIf:$WhatIfPreference; exit 0 }
    catch { Write-Error -ErrorAction Continue "Invoke-Deploy.ps1 failed: $($_.Exception.Message)"; exit 1 }
}
#endregion Main execution
