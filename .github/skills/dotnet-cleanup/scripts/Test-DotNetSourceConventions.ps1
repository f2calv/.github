#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
Audits tracked C# source for central structural and naming conventions.
.DESCRIPTION
Runs read-only layout, naming, constructor, and ILogger-template checks against tracked C# files.
Generated files and EF migrations are excluded by default.
.PARAMETER RepositoryPath
Git repository root to audit.
.PARAMETER Audit
Audit groups: All, Layout, Naming, Constructors, or Logging.
.PARAMETER IncludeGenerated
Includes generated files and EF migrations.
.PARAMETER FailOnFindings
Returns exit code 1 when findings exist.
.EXAMPLE
./Test-DotNetSourceConventions.ps1 -RepositoryPath C:\src\example -Audit Layout -FailOnFindings
#>
[CmdletBinding()]
param(
    [string] $RepositoryPath = '',
    [ValidateSet('All', 'Layout', 'Naming', 'Constructors', 'Logging')][string[]] $Audit = @('All'),
    [switch] $IncludeGenerated,
    [switch] $FailOnFindings
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

function Invoke-AuditGit {
    param([string] $Root, [string[]] $Arguments)
    $output = @(& git -C $Root @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "git failed: git -C $Root $($Arguments -join ' ')" }
    return $output
}

function Get-TrackedCSharpFile {
    param([string] $Root, [switch] $IncludeGenerated)
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    $gitRoot = @(Invoke-AuditGit $resolved @('rev-parse', '--show-toplevel'))[0]
    if ((Resolve-Path -LiteralPath $gitRoot).Path -cne $resolved) {
        throw "RepositoryPath must be the Git root: $gitRoot"
    }
    $paths = @(Invoke-AuditGit $resolved @('ls-files', '--', '*.cs'))
    if (!$IncludeGenerated) {
        $paths = @($paths | Where-Object {
                $_ -notmatch '(?i)(^|/)Migrations/' -and $_ -notmatch '(?i)(\.g|\.generated|\.designer)\.cs$'
            })
    }
    return @($paths | Sort-Object | ForEach-Object {
            $fullPath = [IO.Path]::GetFullPath((Join-Path $resolved $_))
            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                [pscustomobject]@{ RelativePath = $_; FullPath = $fullPath }
            }
        })
}

function Get-MaskedCSharpText {
    param([string] $Text)
    $characters = $Text.ToCharArray()
    $result = [char[]]::new($characters.Length)
    $index = 0
    while ($index -lt $characters.Length) {
        $current = $characters[$index]
        $next = [char]0
        if ($index + 1 -lt $characters.Length) { $next = $characters[$index + 1] }
        if ($current -eq '/' -and $next -eq '/') {
            while ($index -lt $characters.Length -and $characters[$index] -ne "`n") {
                $result[$index] = ' '
                $index++
            }
            continue
        }
        if ($current -eq '/' -and $next -eq '*') {
            $result[$index] = ' '
            $index++
            $result[$index] = ' '
            $index++
            while ($index -lt $characters.Length) {
                if ($characters[$index] -eq '*' -and $index + 1 -lt $characters.Length -and $characters[$index + 1] -eq '/') { break }
                if ($characters[$index] -eq "`n") { $result[$index] = "`n" }
                else { $result[$index] = ' ' }
                $index++
            }
            if ($index + 1 -lt $characters.Length) {
                $result[$index] = ' '
                $index++
                $result[$index] = ' '
                $index++
            }
            continue
        }
        if (($current -eq '@' -or $current -eq '$') -and $next -eq '"') {
            $result[$index] = ' '
            $index++
            $current = $characters[$index]
        }
        if ($current -eq '"') {
            $result[$index] = ' '
            $index++
            while ($index -lt $characters.Length) {
                if ($characters[$index] -eq '\' -and $index + 1 -lt $characters.Length) {
                    $result[$index] = ' '
                    $index++
                    $result[$index] = ' '
                    $index++
                    continue
                }
                if ($characters[$index] -eq '"') {
                    $result[$index] = ' '
                    $index++
                    break
                }
                if ($characters[$index] -eq "`n") { $result[$index] = "`n" }
                else { $result[$index] = ' ' }
                $index++
            }
            continue
        }
        if ($current -eq "'") {
            $result[$index] = ' '
            $index++
            while ($index -lt $characters.Length -and $characters[$index] -ne "'") {
                $result[$index] = ' '
                $index++
            }
            if ($index -lt $characters.Length) {
                $result[$index] = ' '
                $index++
            }
            continue
        }
        $result[$index] = $current
        $index++
    }
    return -join $result
}

function Get-LineNumber([string] $Text, [int] $Index) {
    return 1 + ([regex]::Matches($Text.Substring(0, $Index), "`n")).Count
}

function Get-BraceDepth([string] $Text, [int] $Index) {
    $depth = 0
    foreach ($character in $Text.Substring(0, $Index).ToCharArray()) {
        if ($character -eq '{') { $depth++ } elseif ($character -eq '}') { $depth-- }
    }
    return $depth
}

function New-Finding([string] $Rule, [pscustomobject] $File, [int] $Line, [string] $Symbol, [string] $Detail) {
    return [pscustomobject]@{ Rule = $Rule; File = $File.RelativePath; Line = $Line; Symbol = $Symbol; Detail = $Detail }
}

function Test-TypeFileName([string] $FileName, [string] $TypeName) {
    $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $partial = ($base -split '\.')[0]
    $generic = $base -replace '\{[^}]+\}', ''
    return @($base, $partial, $generic) -contains $TypeName -or @($base, $partial, $generic) -contains "_$TypeName"
}

function Get-LayoutFindings([pscustomobject] $File) {
    $text = [IO.File]::ReadAllText($File.FullPath)
    $masked = Get-MaskedCSharpText $text
    $regex = [regex]'(?m)^[ \t]*(?:(?:public|internal|file|protected|private|abstract|sealed|static|partial|readonly|ref|unsafe|new)\s+)*(?<Kind>record(?:\s+(?:class|struct))?|class|interface|struct|enum)\s+(?<Name>@?[A-Za-z_]\w*)'
    $types = @($regex.Matches($masked) | ForEach-Object {
            [pscustomobject]@{ Kind = $_.Groups['Kind'].Value; Name = $_.Groups['Name'].Value.TrimStart('@');
                Line = Get-LineNumber $masked $_.Index; Depth = Get-BraceDepth $masked $_.Index 
            }
        })
    if ($types.Count -eq 0) { return @() }
    $minimum = ($types | Measure-Object Depth -Minimum).Minimum
    $top = @($types | Where-Object Depth -EQ $minimum)
    $base = [IO.Path]::GetFileNameWithoutExtension($File.RelativePath)
    $enumFile = $base -eq '_Enums'
    $configGroup = $base -match '^_.+Config$'
    $findings = [Collections.Generic.List[object]]::new()
    if ($top.Count -gt 1 -and !$enumFile -and !$configGroup) {
        $findings.Add((New-Finding 'OneTopLevelTypePerFile' $File $top[1].Line ($top.Name -join ', ') 'Split top-level types into matching files.'))
    }
    if ($enumFile -and @($top | Where-Object Kind -NE 'enum').Count -gt 0) {
        $findings.Add((New-Finding 'EnumFileContainsNonEnum' $File $top[0].Line ($top.Name -join ', ') '_Enums.cs may contain enums only.'))
    }
    if (!$enumFile -and -not ($top | Where-Object { Test-TypeFileName $File.RelativePath $_.Name })) {
        $findings.Add((New-Finding 'FileNameMatchesType' $File $top[0].Line ($top.Name -join ', ') "Filename does not match a top-level type."))
    }
    foreach ($type in $top | Where-Object Kind -EQ 'interface') {
        if ($type.Name -cnotmatch '^I[A-Z]') {
            $findings.Add((New-Finding 'InterfaceName' $File $type.Line $type.Name 'Interface names start with I and uppercase.'))
        }
    }
    return $findings.ToArray()
}

function Get-NamingFindings([pscustomobject] $File) {
    $regex = [regex]'^[ \t]*(?:public|internal|protected)\s+(?:(?:required|override|virtual|abstract|static|new|sealed|async|partial|extern)\s+)*\S+(?:<[^>]+>)?\??\s+(?<Name>[A-Za-z_]\w*)\s*(?:\{|=>|\()'
    $lines = [IO.File]::ReadAllLines($File.FullPath)
    $findings = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $lines.Length; $index++) {
        $match = $regex.Match($lines[$index]); if (!$match.Success) { continue }
        $name = $match.Groups['Name'].Value
        if ($name -ne 'this' -and $name -cnotmatch '^[A-Z]') {
            $findings.Add((New-Finding 'PublicMemberName' $File ($index + 1) $name 'Public and internal members use PascalCase.'))
        }
    }
    return $findings.ToArray()
}

function Get-ConstructorFindings([pscustomobject] $File) {
    $text = Get-MaskedCSharpText ([IO.File]::ReadAllText($File.FullPath))
    $classRegex = [regex]'(?m)^[ \t]*(?:(?:public|internal|file|protected|private|abstract|sealed|partial|unsafe|new)\s+)*class\s+(?<Name>[A-Za-z_]\w*)(?:<[^>{}]+>)?'
    $findings = [Collections.Generic.List[object]]::new()
    foreach ($class in $classRegex.Matches($text)) {
        $after = $text.Substring($class.Index + $class.Length)
        if ($after -match '^\s*\(') { continue }
        $name = $class.Groups['Name'].Value
        $classDepth = Get-BraceDepth $text $class.Index
        $constructors = @([regex]::Matches($after, "(?m)^[ \t]*(?<Access>public|internal|protected|private)\s+$([regex]::Escape($name))\s*\((?<Parameters>[^)]*)\)") | Where-Object {
                (Get-BraceDepth $text ($class.Index + $class.Length + $_.Index)) -eq ($classDepth + 1)
            })
        if ($constructors.Count -ne 1 -or
            $constructors[0].Groups['Access'].Value -ne 'public' -or
            [string]::IsNullOrWhiteSpace($constructors[0].Groups['Parameters'].Value)) { continue }
        $ctor = $constructors[0]
        $constructorTail = $after.Substring($ctor.Index + $ctor.Length)
        if ($constructorTail -notmatch '^\s*\{\s*(?:(?:this\.)?_[A-Za-z_]\w*\s*=\s*[A-Za-z_]\w*\s*;\s*)+\}') { continue }
        $findings.Add((New-Finding 'PrimaryConstructorCandidate' $File (Get-LineNumber $text ($class.Index + $class.Length + $ctor.Index)) $name 'Review for primary-constructor conversion.'))
    }
    return $findings.ToArray()
}

function Get-LoggingFindings([pscustomobject] $File) {
    $logRegex = [regex]'(?:_?[Ll]ogger)\s*\.\s*Log(?:Trace|Debug|Information|Warning|Error|Critical)\s*\('
    $tokenRegex = [regex]'\{[@$]?(?<Name>[A-Za-z_]\w*?)(?:[:,][^}]*)?\}'
    $lines = [IO.File]::ReadAllLines($File.FullPath)
    $findings = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $lines.Length; $index++) {
        $line = $lines[$index]
        if (!$logRegex.IsMatch($line) -or $line -match '\$@?"|@\$"') { continue }
        foreach ($match in $tokenRegex.Matches($line)) {
            $name = $match.Groups['Name'].Value
            if ($name -cnotmatch '^[A-Z]') {
                $findings.Add((New-Finding 'LogTemplateName' $File ($index + 1) $name 'ILogger template names use PascalCase.'))
            }
        }
    }
    return $findings.ToArray()
}

function Invoke-DotNetSourceAudit {
    param([string] $RepositoryPath, [string[]] $Audit = @('All'), [switch] $IncludeGenerated)
    $groups = $Audit -contains 'All' ? @('Layout', 'Naming', 'Constructors', 'Logging') : $Audit
    $findings = [Collections.Generic.List[object]]::new()
    foreach ($file in Get-TrackedCSharpFile $RepositoryPath -IncludeGenerated:$IncludeGenerated) {
        if ($groups -contains 'Layout') { $findings.AddRange([object[]]@(Get-LayoutFindings $file)) }
        if ($groups -contains 'Naming') { $findings.AddRange([object[]]@(Get-NamingFindings $file)) }
        if ($groups -contains 'Constructors') { $findings.AddRange([object[]]@(Get-ConstructorFindings $file)) }
        if ($groups -contains 'Logging') { $findings.AddRange([object[]]@(Get-LoggingFindings $file)) }
    }
    return @($findings | Sort-Object File, Line, Rule)
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([string]::IsNullOrWhiteSpace($RepositoryPath)) { throw 'RepositoryPath is required.' }
        $findings = @(Invoke-DotNetSourceAudit $RepositoryPath $Audit -IncludeGenerated:$IncludeGenerated)
        if ($findings.Count -eq 0) { Write-Host 'No .NET source convention findings.' -ForegroundColor Green }
        else { $findings | Format-Table Rule, File, Line, Symbol, Detail -AutoSize -Wrap }
        if ($FailOnFindings -and $findings.Count -gt 0) { exit 1 }
        exit 0
    }
    catch { Write-Error -ErrorAction Continue $_; exit 1 }
}
