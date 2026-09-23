#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Generates or checks a repository root EditorConfig from central fragments.
.DESCRIPTION
    Combines the universal baseline with an optional language profile and repository-specific
    override fragments. Generated files are UTF-8 without a byte-order mark and use LF endings.
.PARAMETER RepositoryPath
    Repository root whose .editorconfig file is generated or checked.
.PARAMETER Profile
    Fragment profile to apply after the universal baseline.
.PARAMETER OverridePath
    Optional fragment paths appended in the supplied order for deliberate repository exceptions.
.PARAMETER Check
    Verifies that the tracked .editorconfig matches generated output without modifying it.
.EXAMPLE
    ./.scripts/Set-EditorConfig.ps1 -RepositoryPath ../signalizr -Profile DotNet
.EXAMPLE
    ./.scripts/Set-EditorConfig.ps1 -RepositoryPath ../helm-charts -Profile Base -Check
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryPath = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Base', 'DotNet', 'Go', 'Python', 'Rust', 'Terraform')]
    [string]$Profile = 'Base',

    [Parameter(Mandatory = $false)]
    [string[]]$OverridePath = @(),

    [Parameter(Mandatory = $false)]
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

function Get-NormalizedFragment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "EditorConfig fragment does not exist: $Path"
    }

    return [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").TrimEnd("`r", "`n")
}

function Get-GeneratedEditorConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Base', 'DotNet', 'Go', 'Python', 'Rust', 'Terraform')]
        [string]$Profile,

        [Parameter(Mandatory = $false)]
        [string[]]$OverridePath = @(),

        [Parameter(Mandatory = $true)]
        [string]$FragmentRoot
    )

    $FragmentPaths = @(
        Join-Path $FragmentRoot 'base.editorconfig'
    )

    if ($Profile -ne 'Base') {
        $FragmentPaths += Join-Path $FragmentRoot "$($Profile.ToLowerInvariant()).editorconfig"
    }

    $FragmentPaths += $OverridePath
    $Fragments = @($FragmentPaths | ForEach-Object { Get-NormalizedFragment -Path $_ })
    return ($Fragments -join "`n`n") + "`n"
}

function Set-EditorConfigFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Base', 'DotNet', 'Go', 'Python', 'Rust', 'Terraform')]
        [string]$Profile,

        [Parameter(Mandatory = $false)]
        [string[]]$OverridePath = @(),

        [Parameter(Mandatory = $false)]
        [switch]$Check,

        [Parameter(Mandatory = $true)]
        [string]$FragmentRoot
    )

    $ResolvedRepositoryPath = (Resolve-Path -LiteralPath $RepositoryPath).Path
    $TargetPath = Join-Path $ResolvedRepositoryPath '.editorconfig'
    $Expected = Get-GeneratedEditorConfig `
        -Profile $Profile `
        -OverridePath $OverridePath `
        -FragmentRoot $FragmentRoot
    $Actual = if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
        [IO.File]::ReadAllText($TargetPath).Replace("`r`n", "`n")
    }
    else {
        $null
    }

    if ($Actual -ceq $Expected) {
        return 'Unchanged'
    }

    if ($Check) {
        throw "EditorConfig drift detected: $TargetPath"
    }

    if ($PSCmdlet.ShouldProcess($TargetPath, 'Generate EditorConfig')) {
        [IO.File]::WriteAllText($TargetPath, $Expected, [Text.UTF8Encoding]::new($false))
        return 'Updated'
    }

    return 'Skipped'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
            throw 'RepositoryPath is required.'
        }

        $FragmentRoot = Join-Path $PSScriptRoot '../.config/editorconfig'
        $Result = Set-EditorConfigFile `
            -RepositoryPath $RepositoryPath `
            -Profile $Profile `
            -OverridePath $OverridePath `
            -Check:$Check `
            -FragmentRoot $FragmentRoot `
            -WhatIf:$WhatIfPreference
        Write-Host "EditorConfig: $Result"
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue $_
        exit 1
    }
}