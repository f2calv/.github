#!/usr/bin/env pwsh
#Requires -Version 7.4

<#+
.SYNOPSIS
Audits pre-commit configuration, CI lint gates, and Dependabot coverage.
.DESCRIPTION
Inspects only caller-supplied repository roots and fails when a repository lacks the fleet contract.
.PARAMETER RepositoryPath
One or more explicit Git repository roots.
.EXAMPLE
./Test-PreCommitFleet.ps1 -RepositoryPath C:\src\repo1,C:\src\repo2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RepositoryPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$PSNativeCommandUseErrorActionPreference = $false

function Get-WorkflowJobBlock {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workflow,

        [Parameter(Mandatory = $true)]
        [string]$JobName
    )

    $pattern = "(?ms)^  $([regex]::Escape($JobName)):\s*.*?(?=^  [A-Za-z0-9_-]+:\s*|\z)"
    return [regex]::Match($Workflow, $pattern).Value
}

function Get-PreCommitRepositoryState {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $root = (Resolve-Path -LiteralPath $Path).Path
    & git -C $root rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Not a Git repository: $root"
    }

    $configPath = Join-Path $root '.pre-commit-config.yaml'
    $ciPath = Join-Path $root '.github/workflows/ci.yml'
    $dependabotPath = Join-Path $root '.github/dependabot.yml'
    $hasConfig = Test-Path -LiteralPath $configPath -PathType Leaf
    $hasCi = Test-Path -LiteralPath $ciPath -PathType Leaf
    $hasDependabot = Test-Path -LiteralPath $dependabotPath -PathType Leaf

    $config = if ($hasConfig) { Get-Content -LiteralPath $configPath -Raw } else { '' }
    $ci = if ($hasCi) { Get-Content -LiteralPath $ciPath -Raw } else { '' }
    $dependabot = if ($hasDependabot) { Get-Content -LiteralPath $dependabotPath -Raw } else { '' }
    $releaseBlock = if ($hasCi) { Get-WorkflowJobBlock -Workflow $ci -JobName 'release' } else { '' }
    $hasRelease = -not [string]::IsNullOrWhiteSpace($releaseBlock)

    $hasPrePushDefault = $config -match '(?m)^default_install_hook_types:\s*\[pre-push\]\s*$'
    $hasLintJob = $ci -match '(?m)^  lint:\s*$'
    $releaseNeedsLint = -not $hasRelease -or $releaseBlock -match '(?ms)needs:.*?\blint\b'
    $hasDependabotPreCommit = $dependabot -match '(?m)^\s*-\s+package-ecosystem:\s*["'']?pre-commit["'']?\s*$'

    $hookPairs = @()
    $hookRepo = ''
    foreach ($line in ($config -split "`r?`n")) {
        if ($line -match '^\s*- repo:\s*(.+)$') {
            $hookRepo = $Matches[1].Trim()
        }
        elseif ($line -match '^\s*rev:\s*(.+)$' -and -not [string]::IsNullOrWhiteSpace($hookRepo)) {
            $hookPairs += "$hookRepo@$($Matches[1].Trim())"
        }
    }

    $compliant = $hasConfig -and $hasPrePushDefault -and $hasCi -and $hasLintJob -and $releaseNeedsLint -and $hasDependabotPreCommit
    return [pscustomobject]@{
        Repository          = Split-Path -Leaf $root
        Path                = $root
        Config              = $hasConfig
        PrePushDefault      = $hasPrePushDefault
        Ci                  = $hasCi
        Lint                = $hasLintJob
        ReleaseNeedsLint    = $releaseNeedsLint
        DependabotPreCommit = $hasDependabotPreCommit
        Hooks               = $hookPairs -join ', '
        Compliant           = $compliant
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $states = @($RepositoryPath | ForEach-Object { Get-PreCommitRepositoryState -Path $_ })
        $states | Format-Table Repository, Config, PrePushDefault, Ci, Lint, ReleaseNeedsLint, DependabotPreCommit, Compliant -AutoSize
        $failed = @($states | Where-Object { -not $_.Compliant })
        if ($failed.Count -gt 0) {
            throw "Pre-commit fleet audit failed for: $($failed.Repository -join ', ')"
        }
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue $_
        exit 1
    }
}
