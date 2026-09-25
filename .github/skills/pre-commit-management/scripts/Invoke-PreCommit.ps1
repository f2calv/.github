#!/usr/bin/env pwsh
#Requires -Version 7.4

<#+
.SYNOPSIS
Runs or updates pre-commit with a native installation or pinned Docker fallback.
.DESCRIPTION
Prefers an existing pre-commit executable or installed Python module. When neither is available,
builds and uses the skill's pinned Docker image. Git hook installation is native-only and explicit.
.PARAMETER RepoRoot
Repository root containing .pre-commit-config.yaml.
.PARAMETER Mode
Run hooks, update hook revisions, or explicitly install the pre-push hook.
.PARAMETER HookId
Optional hook identifier to run instead of every configured hook.
.PARAMETER Files
Optional repository-relative files passed through --files. Run mode defaults to --all-files.
.PARAMETER ForceDocker
Uses the Docker fallback even when native pre-commit is available.
.PARAMETER ContainerImage
Docker image name used for the fallback.
.PARAMETER CacheVolume
Named Docker volume used for pre-commit hook environments.
.PARAMETER PreCommitVersion
Pinned pre-commit runtime version used when building the fallback image.
.EXAMPLE
./Invoke-PreCommit.ps1 -RepoRoot C:\src\example
.EXAMPLE
./Invoke-PreCommit.ps1 -RepoRoot C:\src\example -HookId markdownlint -Files README.md
.EXAMPLE
./Invoke-PreCommit.ps1 -RepoRoot C:\src\example -Mode Update -ForceDocker
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter()]
    [ValidateSet('Run', 'Update', 'InstallPrePush')]
    [string]$Mode = 'Run',

    [Parameter()]
    [string]$HookId = '',

    [Parameter()]
    [string[]]$Files = @(),

    [Parameter()]
    [switch]$ForceDocker,

    [Parameter()]
    [string]$ContainerImage = 'pre-commit-runner:4.6.2',

    [Parameter()]
    [string]$CacheVolume = 'pre-commit-cache-v4',

    [Parameter()]
    [string]$PreCommitVersion = '4.6.2'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$PSNativeCommandUseErrorActionPreference = $false

function Resolve-RepositoryRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath (Join-Path $resolved '.pre-commit-config.yaml') -PathType Leaf)) {
        throw "No .pre-commit-config.yaml exists at repository root '$resolved'."
    }
    return $resolved
}

function Get-PreCommitArguments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Run', 'Update', 'InstallPrePush')]
        [string]$Operation,

        [Parameter()]
        [string]$SelectedHook = '',

        [Parameter()]
        [string[]]$SelectedFiles = @()
    )

    if ($Operation -ne 'Run' -and (-not [string]::IsNullOrWhiteSpace($SelectedHook) -or $SelectedFiles.Count -gt 0)) {
        throw 'HookId and Files apply only to Run mode.'
    }

    switch ($Operation) {
        'Update' { return @('autoupdate') }
        'InstallPrePush' { return @('install', '--hook-type', 'pre-push') }
        'Run' {
            $arguments = @('run')
            if (-not [string]::IsNullOrWhiteSpace($SelectedHook)) {
                $arguments += $SelectedHook
            }
            if ($SelectedFiles.Count -gt 0) {
                $arguments += '--files'
                $arguments += $SelectedFiles
            }
            else {
                $arguments += '--all-files'
            }
            return $arguments
        }
    }
}

function Test-PreCommitVersionOutput {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [string]$RequiredVersion
    )

    return $Output.Trim() -eq "pre-commit $RequiredVersion"
}

function Get-NativePreCommitCommand {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequiredVersion
    )

    $executable = Get-Command pre-commit -ErrorAction SilentlyContinue
    if ($null -ne $executable) {
        $versionOutput = (& $executable.Source --version 2>$null) -join ''
        if (Test-PreCommitVersionOutput -Output $versionOutput -RequiredVersion $RequiredVersion) {
            return [pscustomobject]@{ FilePath = $executable.Source; Prefix = @() }
        }
    }

    $candidates = @(
        [pscustomobject]@{ Name = 'python3'; Prefix = @('-m', 'pre_commit') },
        [pscustomobject]@{ Name = 'python'; Prefix = @('-m', 'pre_commit') },
        [pscustomobject]@{ Name = 'py'; Prefix = @('-3', '-m', 'pre_commit') }
    )
    foreach ($candidate in $candidates) {
        $python = Get-Command $candidate.Name -ErrorAction SilentlyContinue
        if ($null -eq $python) {
            continue
        }
        $versionOutput = (& $python.Source @($candidate.Prefix + @('--version')) 2>$null) -join ''
        if ($LASTEXITCODE -eq 0 -and (Test-PreCommitVersionOutput -Output $versionOutput -RequiredVersion $RequiredVersion)) {
            return [pscustomobject]@{ FilePath = $python.Source; Prefix = $candidate.Prefix }
        }
    }
    return $null
}

function Invoke-NativePreCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    Push-Location $WorkingDirectory
    try {
        & $Command.FilePath @($Command.Prefix + $Arguments)
        if ($LASTEXITCODE -ne 0) {
            throw "pre-commit exited with code $LASTEXITCODE. Review hook output and modified files."
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-DockerPreCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Image,

        [Parameter(Mandatory = $true)]
        [string]$Volume,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $docker) {
        throw 'Neither native pre-commit nor Docker is available. Install one and retry.'
    }

    & $docker.Source image inspect $Image *> $null
    if ($LASTEXITCODE -ne 0) {
        $skillRoot = Split-Path -Parent $PSScriptRoot
        & $docker.Source build --build-arg "PRE_COMMIT_VERSION=$Version" --tag $Image --file (Join-Path $skillRoot 'Dockerfile') $skillRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to build Docker fallback image '$Image'."
        }
    }

    $dockerArguments = @(
        'run', '--rm',
        '--volume', "${WorkingDirectory}:/src",
        '--volume', "${Volume}:/root/.cache/pre-commit",
        $Image
    ) + $Arguments
    & $docker.Source @dockerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker pre-commit exited with code $LASTEXITCODE. Review hook output and modified files."
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $root = Resolve-RepositoryRoot -Path $RepoRoot
        $arguments = Get-PreCommitArguments -Operation $Mode -SelectedHook $HookId -SelectedFiles $Files
        $nativeCommand = if ($ForceDocker) { $null } else { Get-NativePreCommitCommand -RequiredVersion $PreCommitVersion }

        if ($Mode -eq 'InstallPrePush' -and $null -eq $nativeCommand) {
            throw 'InstallPrePush requires native pre-commit because a container cannot install a usable host Git hook.'
        }

        $executionMode = if ($null -ne $nativeCommand) { 'native' } else { 'Docker' }
        if ($PSCmdlet.ShouldProcess($root, "$Mode pre-commit hooks using $executionMode")) {
            if ($null -ne $nativeCommand) {
                Invoke-NativePreCommit -Command $nativeCommand -Arguments $arguments -WorkingDirectory $root
            }
            else {
                Invoke-DockerPreCommit -Arguments $arguments -WorkingDirectory $root -Image $ContainerImage -Volume $CacheVolume -Version $PreCommitVersion
            }
        }
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue $_
        exit 1
    }
}
