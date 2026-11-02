#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Measures the context cost of Copilot instructions and skills.

.DESCRIPTION
Estimates tokens (characters divided by four) for always-on instructions, the instructions each
sample path loads through applyTo, every skill description and every SKILL.md body, and reports
budget violations. Use it before and after a customization change to see where context is spent.

.PARAMETER Root
The .github folder that contains instructions/ and skills/.

.PARAMETER SamplePath
Workspace-relative paths whose matching scoped instructions are summed.

.PARAMETER AlwaysOnBudget
Token budget for all instructions with applyTo '**' combined.

.PARAMETER SampleBudget
Token budget for the scoped instructions one sample path loads.

.PARAMETER DescriptionBudget
Character budget for one skill description.

.PARAMETER SkillBudget
Byte budget for one SKILL.md file.

.PARAMETER FailOnBudget
Exits 1 when any budget is exceeded.

.EXAMPLE
./Measure-CustomizationContext.ps1 -Root ./.github

.EXAMPLE
./Measure-CustomizationContext.ps1 -Root ./.github -SamplePath 'src/App/App.csproj' -FailOnBudget
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = (Join-Path $PSScriptRoot '../../..'),

    [Parameter(Mandatory = $false)]
    [string[]]$SamplePath = @(
        'src/App/Program.cs', 'src/App/App.csproj', 'src/App/appsettings.json',
        'src/App/Controllers/FooController.cs', 'src/App.Tests/FooTests.cs', 'README.md',
        'docs/guide.md', 'Dockerfile', '.github/workflows/ci.yml', 'main.tf', 'script.ps1'
    ),

    [Parameter(Mandatory = $false)]
    [int]$AlwaysOnBudget = 4000,

    [Parameter(Mandatory = $false)]
    [int]$SampleBudget = 5000,

    [Parameter(Mandatory = $false)]
    [int]$DescriptionBudget = 600,

    [Parameter(Mandatory = $false)]
    [int]$SkillBudget = 16384,

    [Parameter(Mandatory = $false)]
    [switch]$FailOnBudget
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Get-Tokens {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    return [int][Math]::Ceiling($Text.Length / 4)
}

function Get-Sum {
    <# Sums a property; Measure-Object yields no result for empty input, which strict mode rejects. #>
    param([AllowEmptyCollection()][object[]]$Items = @(), [Parameter(Mandatory = $true)][string]$Property)
    $Total = 0
    foreach ($Item in $Items) { $Total += $Item.$Property }
    return $Total
}

function Get-FrontMatter {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $Match = [regex]::Match($Text, '\A---\r?\n(.*?)\r?\n---', 'Singleline')
    if ($Match.Success) { return $Match.Groups[1].Value }
    return ''
}

function ConvertTo-GlobRegex {
    <# Converts an applyTo glob to an anchored regex: **/ matches zero or more folders. #>
    param([Parameter(Mandatory = $true)][string]$Glob)
    $Escaped = [regex]::Escape($Glob.Trim())
    $Escaped = $Escaped.Replace('\*\*/', "`u{1}").Replace('\*\*', "`u{2}").Replace('\*', '[^/]*')
    $Escaped = $Escaped.Replace("`u{1}", '(?:.*/)?').Replace("`u{2}", '.*')
    return "^$Escaped$"
}

function Get-InstructionInfo {
    param([Parameter(Mandatory = $true)][string]$Folder)
    foreach ($File in Get-ChildItem -LiteralPath $Folder -Filter '*.instructions.md' -File) {
        $Text = [IO.File]::ReadAllText($File.FullName)
        $Match = [regex]::Match((Get-FrontMatter $Text), "(?m)^applyTo:\s*['`"]?([^'`"\r\n]*)")
        $Globs = @(if ($Match.Success) { $Match.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } })
        [pscustomobject]@{
            Name     = $File.Name
            Globs    = $Globs
            AlwaysOn = $Globs -contains '**'
            Tokens   = Get-Tokens $Text
        }
    }
}

function Get-SkillInfo {
    param([Parameter(Mandatory = $true)][string]$Folder)
    foreach ($Directory in Get-ChildItem -LiteralPath $Folder -Directory) {
        $Path = Join-Path $Directory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $Path)) { continue }
        $Text = [IO.File]::ReadAllText($Path)
        $Match = [regex]::Match((Get-FrontMatter $Text), "(?m)^description:\s*['`"]?(.*?)['`"]?\r?$")
        [pscustomobject]@{
            Name              = $Directory.Name
            DescriptionLength = $Match.Success ? $Match.Groups[1].Value.Length : 0
            Bytes             = (Get-Item -LiteralPath $Path).Length
            Tokens            = Get-Tokens $Text
        }
    }
}

function Measure-CustomizationContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$SamplePath,
        [Parameter(Mandatory = $true)][int]$AlwaysOnBudget,
        [Parameter(Mandatory = $true)][int]$SampleBudget,
        [Parameter(Mandatory = $true)][int]$DescriptionBudget,
        [Parameter(Mandatory = $true)][int]$SkillBudget
    )

    $Instructions = @(Get-InstructionInfo -Folder (Join-Path $Root 'instructions'))
    $Skills = @(Get-SkillInfo -Folder (Join-Path $Root 'skills'))
    $Findings = [Collections.Generic.List[string]]::new()

    $AlwaysOn = @($Instructions | Where-Object AlwaysOn)
    $AlwaysOnTokens = Get-Sum -Items $AlwaysOn -Property Tokens
    if ($AlwaysOnTokens -gt $AlwaysOnBudget) {
        $Findings.Add("Always-on instructions use $AlwaysOnTokens tokens; budget $AlwaysOnBudget.")
    }

    $Samples = foreach ($Sample in $SamplePath) {
        $Normalized = $Sample.Replace('\', '/')
        $Hits = @($Instructions | Where-Object {
                -not $_.AlwaysOn -and @($_.Globs | Where-Object { $Normalized -match (ConvertTo-GlobRegex $_) }).Count -gt 0
            })
        $Tokens = Get-Sum -Items $Hits -Property Tokens
        if ($Tokens -gt $SampleBudget) {
            $Findings.Add("$Sample loads $Tokens scoped tokens; budget $SampleBudget.")
        }
        [pscustomobject]@{ Path = $Sample; Tokens = $Tokens; Instructions = @($Hits | ForEach-Object Name) }
    }

    foreach ($Skill in $Skills) {
        if ($Skill.DescriptionLength -gt $DescriptionBudget) {
            $Findings.Add("$($Skill.Name) description is $($Skill.DescriptionLength) characters; budget $DescriptionBudget.")
        }
        if ($Skill.Bytes -gt $SkillBudget) {
            $Findings.Add("$($Skill.Name) SKILL.md is $($Skill.Bytes) bytes; budget $SkillBudget.")
        }
    }

    return [pscustomobject]@{
        AlwaysOnTokens    = $AlwaysOnTokens
        AlwaysOn          = @($AlwaysOn | ForEach-Object Name)
        DescriptionTokens = [int][Math]::Ceiling((Get-Sum -Items $Skills -Property DescriptionLength) / 4)
        Samples           = @($Samples)
        LargestSkills     = @($Skills | Sort-Object Bytes -Descending | Select-Object -First 10 Name, Bytes, Tokens)
        Findings          = @($Findings)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Result = Measure-CustomizationContext -Root (Resolve-Path -LiteralPath $Root).Path -SamplePath $SamplePath `
            -AlwaysOnBudget $AlwaysOnBudget -SampleBudget $SampleBudget -DescriptionBudget $DescriptionBudget -SkillBudget $SkillBudget
        Write-Host "Always-on: $($Result.AlwaysOnTokens) tokens ($($Result.AlwaysOn -join ', '))"
        Write-Host "Skill descriptions: $($Result.DescriptionTokens) tokens per session"
        $Result.Samples | Format-Table Path, Tokens, @{ n = 'Instructions'; e = { $_.Instructions -join ' ' } } -AutoSize | Out-Host
        $Result.LargestSkills | Format-Table -AutoSize | Out-Host
        foreach ($Finding in $Result.Findings) { Write-Warning $Finding }
        exit ($FailOnBudget -and $Result.Findings.Count -gt 0) ? 1 : 0
    }
    catch {
        Write-Error -ErrorAction Continue $_
        exit 1
    }
}
