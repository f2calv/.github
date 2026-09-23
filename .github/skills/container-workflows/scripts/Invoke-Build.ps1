#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
	Builds a repository container image through a shared build profile.
.DESCRIPTION
	Centralizes the container build workflows used by application, SignalCli, yamlizr, and
	multi-architecture sample repositories. Repository-root build scripts pass their own root and
	profile to this implementation so repository identity and Git metadata remain caller-derived.
.PARAMETER RepositoryRoot
	Root directory of the repository whose image is built.
.PARAMETER BuildMode
	Build behavior profile selected by the repository shim.
.PARAMETER Push
	Authenticates to GHCR and publishes the image.
.PARAMETER Configuration
	Build configuration. Defaults to Debug for Application and Release for SignalCli and Yamlizr.
.PARAMETER Tag
	Image tag override.
.PARAMETER Version
	Yamlizr assembly version override.
.PARAMETER Platforms
	Comma-separated Docker target platforms.
.PARAMETER ImageName
	Image repository name. Defaults to the repository directory name.
.PARAMETER WorkloadName
	Application profile WORKLOAD build argument.
.PARAMETER Project
	SignalCli profile PROJECT build argument.
.PARAMETER SkipSmokeTest
	Skips the yamlizr post-build startup checks.
.EXAMPLE
	./Invoke-Build.ps1 -RepositoryRoot /src/example -BuildMode Application -Configuration Debug
.EXAMPLE
	./Invoke-Build.ps1 -RepositoryRoot /src/yamlizr -BuildMode Yamlizr -Push
.NOTES
	Requires Docker Buildx. Push builds require GitHub CLI package-write access.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$RepositoryRoot,

    [Parameter(Mandatory)]
    [ValidateSet('Application', 'SignalCli', 'Yamlizr', 'MultiArch')]
    [string]$BuildMode,

    [switch]$Push,

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration,

    [string]$Tag,
    [string]$Version,
    [string]$Platforms,
    [string]$ImageName,
    [string]$WorkloadName = 'CasCap.App.Server',
    [string]$Project = 'samples/GenericHost/GenericHost.csproj',
    [switch]$SkipSmokeTest
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

#region Resolution
function Install-GitVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (Get-Command dotnet-gitversion -ErrorAction SilentlyContinue) { return $true }

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

function Resolve-YamlizrVersion {
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
        [Parameter(Mandatory)][string]$BuildMode,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$Configuration,
        [string]$Platforms,
        [string]$ImageName,
        [switch]$Push
    )

    $repositoryName = Split-Path $RepositoryRoot -Leaf
    $resolvedConfiguration = if ($Configuration) { $Configuration } elseif ($BuildMode -eq 'Application') { 'Debug' } else { 'Release' }
    $resolvedPlatforms = if ($Platforms) {
        $Platforms
    }
    elseif ($BuildMode -eq 'Yamlizr') {
        if ($Push) { 'linux/amd64,linux/arm64,linux/arm/v7' } else { Resolve-HostPlatform }
    }
    elseif ($BuildMode -eq 'SignalCli') {
        'linux/amd64,linux/arm64'
    }
    elseif ($BuildMode -eq 'MultiArch') {
        if ($env:PLATFORM) { $env:PLATFORM } else { 'linux/amd64' }
    }
    else {
        'linux/amd64,linux/arm64,linux/arm/v7'
    }
    $resolvedImageName = if ($ImageName) { $ImageName.ToLowerInvariant() } else { $repositoryName.ToLowerInvariant() }
    return [pscustomobject]@{
        Configuration  = $resolvedConfiguration
        Platforms      = $resolvedPlatforms
        ImageName      = $resolvedImageName
        RepositoryName = $repositoryName
        BuilderName    = if ($BuildMode -eq 'MultiArch') { $repositoryName -replace '-', '' } else { "${resolvedImageName}1" }
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
    param(
        [Parameter(Mandatory)][string]$BuilderName,
        [switch]$Bootstrap
    )

    docker buildx inspect $BuilderName *> $null
    if ($LASTEXITCODE -ne 0) {
        $createArguments = @('buildx', 'create', '--name', $BuilderName)
        if ($Bootstrap) { $createArguments += '--bootstrap' }
        docker @createArguments | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "docker buildx create failed for '$BuilderName'." }
    }
    docker buildx use $BuilderName
    if ($LASTEXITCODE -ne 0) { throw "docker buildx use failed for '$BuilderName'." }
}

function Invoke-YamlizrSmokeTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string]$ExpectedVersion
    )

    Write-Host 'Running the image to prove it starts.' -ForegroundColor Cyan
    $reported = "$(docker run --rm $Image --version)".Trim()
    if ($LASTEXITCODE -ne 0) { throw 'docker run --version failed, so the image does not start.' }
    if (-not $reported.StartsWith($ExpectedVersion)) {
        throw "Expected a version starting with '$ExpectedVersion', got '$reported'."
    }
    docker run --rm $Image generate --help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'docker run generate --help failed.' }
}

function Invoke-StandardBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Settings,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BuildMode,
        [string]$Tag,
        [string]$Version,
        [string]$WorkloadName,
        [string]$Project,
        [switch]$Push,
        [switch]$SkipSmokeTest
    )

    if ($BuildMode -eq 'SignalCli' -and $Settings.Configuration -ne 'Release') {
        throw 'SignalCli container builds support Release configuration only.'
    }
    if ($BuildMode -eq 'Yamlizr' -and $Push -and $Settings.Configuration -eq 'Debug') {
        throw 'A Debug image is built against unpublished local sources and must not be pushed.'
    }

    $resolvedVersion = if ($BuildMode -eq 'Yamlizr') {
        Resolve-YamlizrVersion -RequestedVersion $Version -Required:$Push -RepositoryRoot $RepositoryRoot
    }
    else { $null }
    $resolvedTag = Resolve-BuildTag -ExplicitTag $Tag -Push:$Push -RepositoryRoot $RepositoryRoot -ResolvedVersion $resolvedVersion
    $image = "ghcr.io/f2calv/$($Settings.ImageName):$resolvedTag"
    $dockerfile = if ($Settings.Configuration -eq 'Debug') { 'Dockerfile.Debug' } else { 'Dockerfile' }

    if ($Settings.Configuration -eq 'Debug') {
        $dependencies = if ($BuildMode -eq 'Yamlizr') {
            @('CasCap.Common')
        }
        else {
            Get-DependencyRepositories -DockerfilePath (Join-Path $RepositoryRoot 'Dockerfile.Debug')
        }
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
    if ($BuildMode -eq 'Application') { $arguments += @('--build-arg', "WORKLOAD=$WorkloadName") }
    if ($BuildMode -eq 'SignalCli') { $arguments += @('--build-arg', "PROJECT=$Project") }
    if ($BuildMode -eq 'Yamlizr') { $arguments += @('--build-arg', "VERSION=$resolvedVersion") }
    $arguments += @(
        '--build-arg', "CONFIGURATION=$($Settings.Configuration)",
        '--build-arg', "GIT_REPOSITORY=$($Settings.RepositoryName)",
        '--build-arg', "GIT_BRANCH=$gitBranch",
        '--build-arg', "GIT_COMMIT=$gitCommit",
        '--build-arg', "GIT_TAG=$resolvedTag",
        '--build-arg', 'GITHUB_WORKFLOW=local',
        '--build-arg', 'GITHUB_RUN_ID=0',
        '--build-arg', 'GITHUB_RUN_NUMBER=0',
        '--platform', $Settings.Platforms
    )
    $outputArgument = if ($Push) { '--push' } elseif ($BuildMode -eq 'Yamlizr' -and -not $Settings.Platforms.Contains(',')) { '--load' } else { '--pull' }
    $arguments += @($outputArgument, $RepositoryRoot)
    docker @arguments
    if ($LASTEXITCODE -ne 0) { throw "docker buildx build failed with exit code $LASTEXITCODE." }

    if ($BuildMode -eq 'Yamlizr' -and $outputArgument -eq '--load' -and -not $SkipSmokeTest) {
        Invoke-YamlizrSmokeTest -Image $image -ExpectedVersion $resolvedVersion
    }
    $verb = if ($Push) { 'Pushed' } else { 'Built (not pushed)' }
    Write-Host "${verb}: $image" -ForegroundColor Green
}

function Invoke-MultiArchBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Settings,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $tagValue = 'latest-dev'
    $image = "$($Settings.RepositoryName):$tagValue"
    $output = if ($env:OUTPUT) { $env:OUTPUT } else { '--load' }
    $gitBranch = "$(git -C $RepositoryRoot branch --show-current)".Trim()
    $gitCommit = "$(git -C $RepositoryRoot rev-parse HEAD)".Trim()
    Initialize-BuildxBuilder -BuilderName $Settings.BuilderName -Bootstrap

    docker buildx build --tag $image `
        --label 'GITHUB_RUN_ID=0' --label "IMAGE_NAME=$image" `
        --build-arg "GIT_REPOSITORY=$($Settings.RepositoryName)" `
        --build-arg "GIT_BRANCH=$gitBranch" --build-arg "GIT_COMMIT=$gitCommit" `
        --build-arg "GIT_TAG=$tagValue" --build-arg 'GITHUB_WORKFLOW=n/a' `
        --build-arg 'GITHUB_RUN_ID=0' --build-arg 'GITHUB_RUN_NUMBER=0' `
        --platform $Settings.Platforms --pull $output $RepositoryRoot
    if ($LASTEXITCODE -ne 0) { throw "docker buildx build failed with exit code $LASTEXITCODE." }

    if ($output -ne '--load') {
        Write-Host "Build completed with '$output'; no local image was loaded."
        return
    }
    docker images $Settings.RepositoryName
    Read-Host "Hit ENTER to run the '$image' image (Ctrl-C to quit)"
    docker run --rm -it --name $Settings.RepositoryName $image
}
#endregion Docker

#region Main execution
function Invoke-ContainerBuild {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $resolvedRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $settings = Resolve-BuildSettings -BuildMode $BuildMode -RepositoryRoot $resolvedRoot `
        -Configuration $Configuration -Platforms $Platforms -ImageName $ImageName -Push:$Push
    $target = "container image for $($settings.RepositoryName)"
    if (-not $PSCmdlet.ShouldProcess($target, "Run the $BuildMode build profile")) { return }

    if ($BuildMode -eq 'MultiArch') {
        Invoke-MultiArchBuild -Settings $settings -RepositoryRoot $resolvedRoot
        return
    }
    Invoke-StandardBuild -Settings $settings -RepositoryRoot $resolvedRoot -BuildMode $BuildMode `
        -Tag $Tag -Version $Version -WorkloadName $WorkloadName -Project $Project `
        -Push:$Push -SkipSmokeTest:$SkipSmokeTest
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
