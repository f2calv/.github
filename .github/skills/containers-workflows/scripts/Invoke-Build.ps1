#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
	Builds a repository container image.
.DESCRIPTION
	Centralizes the container build used by every repository, whatever its language. Repository-root
	build scripts pass their own root so repository identity and Git metadata remain caller-derived.
	Without -Push, -Load or -Run the image is built for every target platform into the build cache
	only, which validates the multi-architecture build.
.PARAMETER RepositoryRoot
	Root directory of the repository whose image is built.
.PARAMETER Push
	Authenticates to GHCR and publishes the image.
.PARAMETER Load
	Loads a single-platform image into the local Docker image store. Defaults to the host platform.
.PARAMETER Run
	Loads the image as -Load does, then runs it interactively.
.PARAMETER Configuration
	Build configuration. Defaults to Debug when the repository has a Dockerfile.Debug, else Release.
.PARAMETER Tag
	Image tag override.
.PARAMETER Version
	Application version override, passed as the VERSION build argument.
.PARAMETER Platforms
	Comma-separated Docker target platforms.
.PARAMETER ImageName
	Image repository name. Defaults to the repository directory name.
.PARAMETER WorkloadName
	Optional assembly name passed as the WORKLOAD build argument. When omitted, the Dockerfile
	default selects the assembly.
.EXAMPLE
	./Invoke-Build.ps1 -RepositoryRoot /src/example
.EXAMPLE
	./Invoke-Build.ps1 -RepositoryRoot /src/example -Configuration Release -Run
.EXAMPLE
	./Invoke-Build.ps1 -RepositoryRoot /src/example -Push
.NOTES
	Requires Docker Buildx and a GitHub origin remote. Push builds require GitHub CLI package-write
	access.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$RepositoryRoot,

    [switch]$Push,
    [switch]$Load,
    [switch]$Run,

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration,

    [string]$Tag,
    [string]$Version,
    [string]$Platforms,
    [string]$ImageName,
    [string]$WorkloadName
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

. (Join-Path $PSScriptRoot 'ContainerWorkflows.Common.ps1')

#region Resolution
function Install-GitVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (Get-Command dotnet-gitversion -ErrorAction SilentlyContinue) { return $true }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return $false }

    Write-Host 'dotnet-gitversion not found. Installing GitVersion.Tool globally...' -ForegroundColor Cyan
    dotnet tool install -g GitVersion.Tool
    if ($LASTEXITCODE -ne 0) { return $false }

    $toolsPath = Join-Path $HOME '.dotnet/tools'
    if ($env:PATH -notlike "*$toolsPath*") {
        $env:PATH = "$toolsPath$([IO.Path]::PathSeparator)$env:PATH"
    }
    return [bool](Get-Command dotnet-gitversion -ErrorAction SilentlyContinue)
}

function Resolve-BuildTag {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ExplicitTag,
        [switch]$Push,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$ResolvedVersion
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitTag)) { return $ExplicitTag.ToLowerInvariant() }
    if (-not $Push) { return 'latest-dev' }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedVersion)) { return $ResolvedVersion.ToLowerInvariant() }
    if (-not (Install-GitVersion)) {
        throw 'Failed to install GitVersion.Tool. Run: dotnet tool install -g GitVersion.Tool'
    }
    return "$(dotnet-gitversion $RepositoryRoot /showvariable FullSemVer)".Trim().ToLowerInvariant()
}

function Resolve-Version {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$RequestedVersion,
        [switch]$Required,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedVersion)) { return $RequestedVersion }
    if (Install-GitVersion) {
        $resolved = "$(dotnet-gitversion $RepositoryRoot /showvariable SemVer)".Trim()
        if (-not [string]::IsNullOrWhiteSpace($resolved)) { return $resolved }
    }
    if ($Required) {
        throw 'Could not resolve a version from GitVersion, which a push build requires. Pass -Version.'
    }
    Write-Warning 'Could not resolve a version from GitVersion, falling back to 0.0.1.'
    return '0.0.1'
}

function Resolve-HostPlatform {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    switch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
        'Arm64' { return 'linux/arm64' }
        'Arm' { return 'linux/arm/v7' }
        default { return 'linux/amd64' }
    }
}

function Resolve-BuildSettings {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Configuration,
        [string]$Platforms,
        [string]$ImageName,
        [switch]$Push,
        [switch]$Load
    )

    if ($Push -and $Load) { throw '-Push cannot be combined with -Load or -Run.' }
    $repositoryName = Split-Path $RepositoryRoot -Leaf
    $resolvedConfiguration = if ($Configuration) {
        $Configuration
    }
    elseif (Test-Path -LiteralPath (Join-Path $RepositoryRoot 'Dockerfile.Debug') -PathType Leaf) {
        'Debug'
    }
    else {
        'Release'
    }
    $resolvedPlatforms = if ($Platforms) {
        $Platforms
    }
    elseif ($Load) {
        Resolve-HostPlatform
    }
    else {
        'linux/amd64,linux/arm64,linux/arm/v7'
    }
    if ($Load -and $resolvedPlatforms.Contains(',')) {
        throw 'A multi-platform image cannot be loaded into the local image store. Select one platform.'
    }
    $resolvedImageName = if ($ImageName) { $ImageName.ToLowerInvariant() } else { $repositoryName.ToLowerInvariant() }
    return [pscustomobject]@{
        Configuration  = $resolvedConfiguration
        Platforms      = $resolvedPlatforms
        ImageName      = $resolvedImageName
        RepositoryName = $repositoryName
        BuilderName    = "${resolvedImageName}1"
    }
}
#endregion Resolution

#region Dependencies and authentication
function Get-DependencyRepositories {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$DockerfilePath)

    $repositories = @([regex]::Matches(
            [IO.File]::ReadAllText($DockerfilePath),
            '(?m)^\s*COPY\s+deps/([^/\s]+)\s+/'
        ) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($repositories.Count -eq 0) {
        throw "No sibling dependencies were found in '$DockerfilePath'."
    }
    return $repositories
}

function Sync-Dependencies {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$DependencyRepositories
    )

    $parent = Split-Path $RepositoryRoot -Parent
    foreach ($repository in $DependencyRepositories) {
        $source = Join-Path $parent $repository
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "A Debug build requires sibling repository '$repository' at '$source'."
        }
        $destination = Join-Path (Join-Path $RepositoryRoot 'deps') $repository
        $resolvedSource = [IO.Path]::GetFullPath($source).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $resolvedDestination = [IO.Path]::GetFullPath($destination).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($resolvedDestination.StartsWith("$resolvedSource$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to mirror '$resolvedSource' into its own descendant '$resolvedDestination'."
        }
        if (-not $PSCmdlet.ShouldProcess($repository, 'Mirror sibling repository into deps/')) { continue }

        Write-Host "Syncing $repository -> deps/$repository" -ForegroundColor Cyan
        if ($IsWindows) {
            robocopy $source $destination /MIR /XD bin obj .git .vs node_modules deps `
                /XF 'appsettings.Local*.json' '*.user' /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $repository with exit code $LASTEXITCODE." }
            $global:LASTEXITCODE = 0
            continue
        }
        if (-not (Get-Command rsync -ErrorAction SilentlyContinue)) {
            throw 'rsync not found. Install it to mirror local sibling dependencies on this platform.'
        }
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        rsync -a --delete --exclude 'bin/' --exclude 'obj/' --exclude '.git/' --exclude '.vs/' `
            --exclude 'node_modules/' --exclude 'deps/' --exclude 'appsettings.Local*.json' `
            --exclude '*.user' "$source/" "$destination/"
        if ($LASTEXITCODE -ne 0) { throw "rsync failed for $repository with exit code $LASTEXITCODE." }
    }
}

function Connect-Ghcr {
    [CmdletBinding()]
    param()

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'gh CLI not found. Install it from https://cli.github.com'
    }
    if (-not (gh auth status 2>&1 | Select-String -SimpleMatch 'write:packages')) {
        Write-Host 'Refreshing gh auth to add the write:packages scope...' -ForegroundColor Cyan
        gh auth refresh -h github.com -s write:packages
        if ($LASTEXITCODE -ne 0) { throw 'gh auth refresh failed.' }
    }
    $ghUser = "$(gh api user --jq .login)".Trim()
    Write-Host "Authenticating Docker to ghcr.io as $ghUser..." -ForegroundColor Cyan
    gh auth token | docker login ghcr.io -u $ghUser --password-stdin
    if ($LASTEXITCODE -ne 0) { throw 'docker login ghcr.io failed.' }
}
#endregion Dependencies and authentication

#region Docker
function Initialize-BuildxBuilder {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BuilderName)

    docker buildx inspect $BuilderName *> $null
    if ($LASTEXITCODE -ne 0) {
        docker buildx create --name $BuilderName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "docker buildx create failed for '$BuilderName'." }
    }
    docker buildx use $BuilderName
    if ($LASTEXITCODE -ne 0) { throw "docker buildx use failed for '$BuilderName'." }
}

function Invoke-ImageBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Settings,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Tag,
        [string]$Version,
        [string]$WorkloadName,
        [switch]$Push,
        [switch]$Load,
        [switch]$Run
    )

    $resolvedVersion = Resolve-Version -RequestedVersion $Version -Required:$Push -RepositoryRoot $RepositoryRoot
    $resolvedTag = Resolve-BuildTag -ExplicitTag $Tag -Push:$Push -RepositoryRoot $RepositoryRoot -ResolvedVersion $resolvedVersion
    $image = "ghcr.io/$(Get-GitHubOwner -RepositoryRoot $RepositoryRoot)/$($Settings.ImageName):$resolvedTag"
    $dockerfile = if ($Settings.Configuration -eq 'Debug') { 'Dockerfile.Debug' } else { 'Dockerfile' }

    if ($Settings.Configuration -eq 'Debug') {
        $dependencies = Get-DependencyRepositories -DockerfilePath (Join-Path $RepositoryRoot 'Dockerfile.Debug')
        Sync-Dependencies -RepositoryRoot $RepositoryRoot -DependencyRepositories $dependencies
    }
    if ($Push) { Connect-Ghcr }
    Initialize-BuildxBuilder -BuilderName $Settings.BuilderName

    $gitBranch = "$(git -C $RepositoryRoot branch --show-current)".Trim()
    if ($LASTEXITCODE -ne 0) { throw "git branch failed for '$RepositoryRoot'." }
    $gitCommit = "$(git -C $RepositoryRoot rev-parse HEAD)".Trim()
    if ($LASTEXITCODE -ne 0) { throw "git rev-parse failed for '$RepositoryRoot'." }

    $arguments = @(
        'buildx', 'build', '--tag', $image,
        '--file', (Join-Path $RepositoryRoot $dockerfile)
    )
    if (-not [string]::IsNullOrWhiteSpace($WorkloadName)) {
        $arguments += @('--build-arg', "WORKLOAD=$WorkloadName")
    }
    $arguments += @('--build-arg', "VERSION=$resolvedVersion")
    $arguments += @(
        '--build-arg', "CONFIGURATION=$($Settings.Configuration)",
        '--build-arg', "GIT_REPOSITORY=$($Settings.RepositoryName)",
        '--build-arg', "GIT_BRANCH=$gitBranch",
        '--build-arg', "GIT_COMMIT=$gitCommit",
        '--build-arg', "GIT_TAG=$resolvedTag",
        '--build-arg', 'GITHUB_WORKFLOW=local',
        '--build-arg', 'GITHUB_RUN_ID=0',
        '--build-arg', 'GITHUB_RUN_NUMBER=0',
        '--platform', $Settings.Platforms,
        '--pull'
    )
    if ($Push) { $arguments += '--push' }
    elseif ($Load -or $Run) { $arguments += '--load' }
    $arguments += $RepositoryRoot
    docker @arguments
    if ($LASTEXITCODE -ne 0) { throw "docker buildx build failed with exit code $LASTEXITCODE." }

    $verb = if ($Push) { 'Pushed' } elseif ($Load -or $Run) { 'Loaded' } else { 'Built into the cache only' }
    Write-Host "${verb}: $image ($($Settings.Platforms))" -ForegroundColor Green
    if ($Run) { docker run --rm -it $image }
}
#endregion Docker

#region Main execution
function Invoke-ContainerBuild {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $resolvedRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $settings = Resolve-BuildSettings -RepositoryRoot $resolvedRoot -Configuration $Configuration `
        -Platforms $Platforms -ImageName $ImageName -Push:$Push -Load:($Load -or $Run)
    $target = "$($settings.Configuration) container image for $($settings.RepositoryName)"
    if (-not $PSCmdlet.ShouldProcess($target, 'Build')) { return }

    Invoke-ImageBuild -Settings $settings -RepositoryRoot $resolvedRoot -Tag $Tag -Version $Version `
        -WorkloadName $WorkloadName -Push:$Push -Load:$Load -Run:$Run
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-ContainerBuild -WhatIf:$WhatIfPreference
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Invoke-Build.ps1 failed: $($_.Exception.Message)"
        exit 1
    }
}
#endregion Main execution
