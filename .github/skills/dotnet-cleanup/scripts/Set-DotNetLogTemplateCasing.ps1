#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
Capitalizes lowercase ILogger message-template names in tracked C# source.
.DESCRIPTION
Finds single-line ILogger calls and changes template names such as {userId} to {UserId}. String
interpolation is excluded. Use Check for a read-only gate and WhatIf to preview writes.
.PARAMETER RepositoryPath
Git repository root to inspect.
.PARAMETER Check
Returns exit code 1 when changes would be required without modifying files.
.EXAMPLE
./Set-DotNetLogTemplateCasing.ps1 -RepositoryPath C:\src\example -Check
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RepositoryPath = '',
    [switch] $Check
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

function Invoke-LogFixGit {
    param([string] $Root, [string[]] $Arguments)
    $output = @(& git -C $Root @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "git failed: git -C $Root $($Arguments -join ' ')" }
    return $output
}

function Get-TrackedLogSource {
    param([string] $RepositoryPath)
    $root = (Resolve-Path -LiteralPath $RepositoryPath).Path
    $gitRoot = @(Invoke-LogFixGit $root @('rev-parse', '--show-toplevel'))[0]
    if ((Resolve-Path -LiteralPath $gitRoot).Path -cne $root) {
        throw "RepositoryPath must be the Git root: $gitRoot"
    }
    return @(Invoke-LogFixGit $root @('ls-files', '--', '*.cs') | ForEach-Object {
            [pscustomobject]@{ RelativePath = $_; FullPath = [IO.Path]::GetFullPath((Join-Path $root $_)) }
        })
}

function Set-LogTemplateCasing {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RepositoryPath, [switch] $Check)

    $logRegex = [regex]'(?m)^.*(?:_?[Ll]ogger)\s*\.\s*Log(?:Trace|Debug|Information|Warning|Error|Critical)\s*\(.*$'
    $tokenRegex = [regex]'\{(?<Prefix>[@$]?)(?<Name>[a-z]\w*)(?<Suffix>(?:[:,][^}]*)?)\}'
    $results = [Collections.Generic.List[object]]::new()
    foreach ($file in Get-TrackedLogSource $RepositoryPath) {
        $text = [IO.File]::ReadAllText($file.FullPath)
        $replacementCounts = [Collections.Generic.List[int]]::new()
        $updatedText = $logRegex.Replace($text, {
                param($lineMatch)
                $line = $lineMatch.Value
                if ($line -match '\$@?"|@\$"') { return $line }
                $lineMatches = $tokenRegex.Matches($line)
                if ($lineMatches.Count -eq 0) { return $line }
                $replacementCounts.Add($lineMatches.Count)
                return $tokenRegex.Replace($line, {
                        param($match)
                        $name = $match.Groups['Name'].Value
                        return "{$($match.Groups['Prefix'].Value)$([char]::ToUpperInvariant($name[0]))$($name.Substring(1))$($match.Groups['Suffix'].Value)}"
                    })
            })
        if ($updatedText -ceq $text) { continue }
        $replacementCount = ($replacementCounts | Measure-Object -Sum).Sum
        $results.Add([pscustomobject]@{ File = $file.RelativePath; Replacements = $replacementCount })
        if (!$Check -and $PSCmdlet.ShouldProcess($file.RelativePath, 'Capitalize ILogger template names')) {
            [IO.File]::WriteAllText($file.FullPath, $updatedText)
        }
    }
    return $results.ToArray()
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([string]::IsNullOrWhiteSpace($RepositoryPath)) { throw 'RepositoryPath is required.' }
        $changes = @(Set-LogTemplateCasing $RepositoryPath -Check:$Check -WhatIf:$WhatIfPreference)
        if ($changes.Count -eq 0) { Write-Host 'No ILogger template casing changes required.' -ForegroundColor Green }
        else { $changes | Format-Table File, Replacements -AutoSize }
        if ($Check -and $changes.Count -gt 0) { exit 1 }
        exit 0
    }
    catch { Write-Error -ErrorAction Continue $_; exit 1 }
}
