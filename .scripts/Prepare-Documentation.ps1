#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Stages reviewed Git-tracked Markdown and documentation assets for MkDocs.
.PARAMETER RepoRoot
    Repository containing the canonical documentation sources.
.EXAMPLE
    ./.scripts/Prepare-Documentation.ps1 -RepoRoot .
#>
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

#region Functions
function Invoke-DocumentationPreparation {
    <#
    .SYNOPSIS
        Creates the dedicated staging directory from tracked public documentation only.
    .PARAMETER RepoRoot
        Repository containing the canonical documentation sources.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $Root = (Resolve-Path -LiteralPath $RepoRoot).Path
    $Tracked = @(& git -C $Root -c core.quotePath=false ls-files)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate tracked documentation; verify the repository.' }
    $Sources = @($Tracked | Where-Object {
            $_ -match '^[^/]+\.md$|^(docs/|\.github/(instructions|skills|prompts)/).*\.md$|^docs/assets/' -and
            $_ -notmatch '(^|/)(tests|fixtures|examples|bin|obj)/'
        })
    if ($Sources.Count -eq 0) { throw 'No tracked documentation was selected; stage the intended public sources first.' }
    $Destination = Join-Path $Root '.docs-source'
    $Marker = Join-Path $Destination '.documentation-stage'
    if (Test-Path -LiteralPath $Destination) {
        if (-not (Test-Path -LiteralPath $Marker -PathType Leaf)) {
            throw 'The documentation staging directory is not owned by this tool; preserve it and choose a clean repository directory.'
        }
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    [void][IO.Directory]::CreateDirectory($Destination)
    [IO.File]::WriteAllText($Marker, "tracked-public-documentation`n")
    foreach ($Source in $Sources) {
        $Original = Join-Path $Root $Source
        $Item = Get-Item -LiteralPath $Original
        if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'A documentation source is a symbolic link; review it before publishing.'
        }
        $Target = Join-Path $Destination $Source
        [void][IO.Directory]::CreateDirectory((Split-Path $Target -Parent))
        Copy-Item -LiteralPath $Original -Destination $Target
    }
    return $Sources.Count
}
#endregion Functions

#region Main Execution
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Count = Invoke-DocumentationPreparation -RepoRoot $RepoRoot
        Write-Host "Staged $Count tracked documentation sources."
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue $_.Exception.Message
        exit 1
    }
}
#endregion Main Execution
