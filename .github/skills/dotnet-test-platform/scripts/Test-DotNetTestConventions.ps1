#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Reports likely drift from the xUnit test classification and selection rules.
.DESCRIPTION
Reads tracked source and workflow files at explicitly supplied Git roots. This
heuristic audit does not compile C#, evaluate MSBuild, or prove fixture safety.
.PARAMETER RepositoryPath
One or more Git repository roots.
.PARAMETER FailOnFindings
Returns exit code 1 when any finding is reported.
.EXAMPLE
./Test-DotNetTestConventions.ps1 -RepositoryPath . -FailOnFindings
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]] $RepositoryPath,
    [switch] $FailOnFindings
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$PSNativeCommandUseErrorActionPreference = $false

#region Audit
function Get-TestFinding {
    param([string] $Path, [string] $Text, [string] $Root)

    if ($Path -match '\.(ya?ml|jsonc?)$') {
        $commands = ($Text -split '\r?\n' | Where-Object {
            $_ -notmatch '^\s*(?:#|description:|"description"\s*:)'
        }) -join "`n"
        if ($commands -match '(?i)--filter(?:-not)?-trait[^\r\n]*Category\s*=\s*Unit\b') { 'UnitFilter' }
        if ($commands -match '(?i)--filter-not-trait[^\r\n]*Category\s*=\s*Integration\b') { 'BroadIntegrationExclusion' }
        if ($commands -match '(?i)--filter(?:-class|-method)?[^\r\n]*[\\/]Tests[\\/](?:Unit|Integration)\b') { 'FolderFilter' }
        return
    }

    $code = [regex]::Replace($Text, '(?m)^[ \t]*(?://[^\r\n]*|/\*[\s\S]*?\*/)', '')
    if ($code -notmatch '(?m)^\s*\[(?:[\w.]*\.)?\w*(?:Fact|Theory)(?:Attribute)?\b') { return }
    $integration = 'Trait(?:Attribute)?\s*\(\s*"Category"\s*,\s*"Integration"\s*\)'
    $live = 'Trait(?:Attribute)?\s*\(\s*"Category"\s*,\s*"Live"\s*\)'
    $classAttributes = ''
    if ($code -match '\bpartial\s+class\s+(?<name>\w+)') {
        $name = [regex]::Escape($Matches.name)
        $namespace = [regex]::Match($code, '\bnamespace\s+[\w.]+').Value
        $directory = Split-Path -Parent (Join-Path $Root $Path)
        foreach ($part in (Get-ChildItem -LiteralPath $directory -Filter '*.cs' -File)) {
            $partCode = [IO.File]::ReadAllText($part.FullName)
            if ([regex]::Match($partCode, '\bnamespace\s+[\w.]+').Value -cne $namespace) { continue }
            $header = [regex]::Match($partCode, "(?m)(?<attributes>(?:^[ \t]*\[[^\r\n]+\][ \t]*\r?\n)+)[ \t]*(?:\w+\s+)*partial\s+class\s+$name\b")
            $classAttributes += $header.Groups['attributes'].Value
        }
    }
    $classification = $code + $classAttributes
    if ($code -match 'Trait(?:Attribute)?\s*\(\s*"Category"\s*,\s*"Unit"\s*\)') { 'RedundantUnitTrait' }
    if ($Path -match '/Integration/' -and $classification -notmatch $integration) {
        if ($classification -match 'Trait(?:Attribute)?\s*\(\s*\w+\.\w+') { 'ReviewNonLiteralTrait' }
        else { 'MissingIntegrationTrait' }
    }
    if ($classification -match $live -and $classification -notmatch $integration) { 'LiveWithoutIntegration' }
    if ($Path -match '/Unit/' -and $classification -match $integration -and $classification -notmatch $live) { 'IntegrationInUnitFolder' }
    if ($Path -match '/(?:Live|LiveRuntime)/' -and $classification -notmatch $live) { 'MissingLiveTrait' }
}
#endregion

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $git = (Get-Command git -CommandType Application -TotalCount 1).Source
        $findingCount = 0
        foreach ($repository in $RepositoryPath) {
            $root = (Resolve-Path -LiteralPath $repository).ProviderPath
            $prefix = & $git --no-pager -C $root rev-parse --show-prefix
            if ($LASTEXITCODE -ne 0 -or $prefix) { throw "Supply a Git repository root: $repository" }
            $files = @(& $git --no-pager -C $root -c core.quotepath=false ls-files -- '*.cs' '.github/workflows/*' '.vscode/tasks.json')
            if ($LASTEXITCODE -ne 0) { throw "Could not enumerate tracked files in $repository." }
            foreach ($file in $files) {
                if ($file -match '\.cs$' -and $file -notmatch '(?:^|/)[^/]*Tests?(/|$)') { continue }
                $path = Join-Path $root $file
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
                foreach ($rule in (Get-TestFinding -Path $file -Text ([IO.File]::ReadAllText($path)) -Root $root)) {
                    $findingCount++
                    Write-Output ([pscustomobject]@{ Repository = $root; Path = $file; Rule = $rule })
                }
            }
        }
        Write-Verbose "$findingCount finding(s)."
        if ($FailOnFindings -and $findingCount -gt 0) { exit 1 }
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue $_
        exit 1
    }
}
