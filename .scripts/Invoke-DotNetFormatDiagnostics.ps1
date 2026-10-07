#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Applies or verifies one family of .NET formatter diagnostics project by project.
.DESCRIPTION
    Discovers tracked C# projects in an explicit repository, routes IDE diagnostics through
    `dotnet format style` and CA diagnostics through `dotnet format analyzers`, then invokes the
    formatter separately for each project to avoid multi-target solution rewrite conflicts.
.PARAMETER RepositoryPath
    Git repository root containing the projects to format.
.PARAMETER Diagnostic
    One or more diagnostics from a single family: IDE diagnostics or CA diagnostics.
.PARAMETER ProjectPath
    Optional tracked project paths, relative to the repository root or absolute. Defaults to every
    tracked .csproj file in the repository.
.PARAMETER Check
    Verifies that formatting would make no changes.
.EXAMPLE
    ./.scripts/Invoke-DotNetFormatDiagnostics.ps1 -RepositoryPath ../agentizr -Diagnostic IDE0040
.EXAMPLE
    ./.scripts/Invoke-DotNetFormatDiagnostics.ps1 -RepositoryPath ../agentizr -Diagnostic CA1859,CA1861 -Check
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepositoryPath = '',

    [Parameter(Mandatory = $false)]
    [string[]]$Diagnostic = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$ProjectPath = @(),

    [Parameter(Mandatory = $false)]
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

function Get-DotNetFormatSubcommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Diagnostic
    )

    if ($Diagnostic.Count -eq 0) {
        throw 'At least one diagnostic is required.'
    }

    $InvalidDiagnostics = @($Diagnostic | Where-Object { $_ -notmatch '^(IDE|CA)\d{4}$' })
    if ($InvalidDiagnostics.Count -gt 0) {
        throw "Unsupported diagnostic identifiers: $($InvalidDiagnostics -join ', '). Use IDE#### or CA#### identifiers."
    }

    $Families = @($Diagnostic | ForEach-Object { if ($_ -match '^IDE') { 'style' } else { 'analyzers' } } | Sort-Object -Unique)
    if ($Families.Count -ne 1) {
        throw 'IDE and CA diagnostics must be run as separate formatter families.'
    }

    return $Families[0]
}

function Invoke-GitCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Output = @(& git @Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "git command failed with exit code ${LASTEXITCODE}: git $($Arguments -join ' ')"
    }

    return $Output
}

function Get-TrackedDotNetProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryPath,

        [Parameter(Mandatory = $false)]
        [string[]]$ProjectPath = @()
    )

    $ResolvedRepositoryPath = (Resolve-Path -LiteralPath $RepositoryPath).Path
    $GitRoot = @(Invoke-GitCommand -Arguments @('-C', $ResolvedRepositoryPath, 'rev-parse', '--show-toplevel'))[0]
    $ResolvedGitRoot = (Resolve-Path -LiteralPath $GitRoot).Path
    if ($ResolvedGitRoot -cne $ResolvedRepositoryPath) {
        throw "RepositoryPath must be the Git repository root: $ResolvedGitRoot"
    }

    $TrackedProjects = @(Invoke-GitCommand -Arguments @('-C', $ResolvedRepositoryPath, 'ls-files', '--', '*.csproj'))
    if ($TrackedProjects.Count -eq 0) {
        throw "No tracked .csproj files were found in $ResolvedRepositoryPath"
    }

    $TrackedByFullPath = @{}
    foreach ($RelativePath in $TrackedProjects) {
        $FullPath = [IO.Path]::GetFullPath((Join-Path $ResolvedRepositoryPath $RelativePath))
        $TrackedByFullPath[$FullPath] = $true
    }

    $SelectedProjects = if ($ProjectPath.Count -eq 0) {
        @($TrackedByFullPath.Keys)
    }
    else {
        @($ProjectPath | ForEach-Object {
                $Candidate = if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $ResolvedRepositoryPath $_ }
                [IO.Path]::GetFullPath($Candidate)
            })
    }

    foreach ($SelectedProject in $SelectedProjects) {
        if (-not $TrackedByFullPath.ContainsKey($SelectedProject)) {
            throw "Project is not a tracked .csproj in the repository: $SelectedProject"
        }
    }

    return @($SelectedProjects | Sort-Object -Unique)
}

function Invoke-DotNetFormatCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet format failed with exit code $LASTEXITCODE for project $($Arguments[1])"
    }
}

function Invoke-DotNetFormatDiagnostics {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Diagnostic,

        [Parameter(Mandatory = $false)]
        [string[]]$ProjectPath = @(),

        [Parameter(Mandatory = $false)]
        [switch]$Check
    )

    $Subcommand = Get-DotNetFormatSubcommand -Diagnostic $Diagnostic
    $Projects = @(Get-TrackedDotNetProject -RepositoryPath $RepositoryPath -ProjectPath $ProjectPath)

    foreach ($Project in $Projects) {
        $Arguments = @('format', $Project, $Subcommand, '--diagnostics') + $Diagnostic + @('--no-restore', '--verbosity', 'minimal')
        if ($Check) {
            $Arguments += '--verify-no-changes'
        }

        if ($Check -or $PSCmdlet.ShouldProcess($Project, "Run dotnet format $Subcommand for $($Diagnostic -join ', ')")) {
            Write-Host "Formatting: $Project [$($Diagnostic -join ', ')]"
            Invoke-DotNetFormatCommand -Arguments $Arguments
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
            throw 'RepositoryPath is required.'
        }

        Invoke-DotNetFormatDiagnostics `
            -RepositoryPath $RepositoryPath `
            -Diagnostic $Diagnostic `
            -ProjectPath $ProjectPath `
            -Check:$Check `
            -WhatIf:$WhatIfPreference
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue $_
        exit 1
    }
}
