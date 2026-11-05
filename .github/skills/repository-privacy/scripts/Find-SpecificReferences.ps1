#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Finds owner-, project- and author-specific references in shared, public guidance files.

.DESCRIPTION
    Shared instructions and skills must read sensibly in any repository. This scanner seeds itself
    from the repository owner's GitHub account at runtime, so it contains no private value:

      - Private repository names are errors: they must not appear anywhere.
      - The configured author name and caller-supplied terms are errors.
      - Public repository names and the owner login are reviewed. They may appear as example
        libraries ("for example", "such as"), inside a section headed "Real-World Example", in files
        whose name contains "real-world-example", in files under an examples or templates folder, and
        later in a file that has already introduced the same name as an example; anywhere else
        they are reported for review.

    References to the scanned repository itself are ignored. Names that are one all-lowercase or
    all-uppercase word, such as "rust" or "KNX", collide with ordinary technical words, so they match
    only with an owner prefix (owner/name) unless -IncludeAmbiguous is set. Names that start with "."
    always need the owner prefix.

.PARAMETER RepoRoot
    Repository to scan. Defaults to the repository containing this script.

.PARAMETER Path
    Repository-relative paths whose tracked files are scanned. Defaults to the shared guidance:
    copilot-instructions.md and the instructions, skills, prompts and agents folders under .github.
    Comma-joined values, as passed by pwsh -File, are split.

.PARAMETER Exclude
    Wildcard patterns, matched against repository-relative paths with / separators, to skip.
    Defaults to test folders, whose fixtures are synthetic.

.PARAMETER Owner
    GitHub owner whose repositories seed the scan. Defaults to the authenticated gh user.

.PARAMETER Repository
    Repository seeds as objects with Name, Visibility (PUBLIC, PRIVATE or INTERNAL) and optional
    IsFork. Defaults to every repository of -Owner listed by gh.

.PARAMETER AuthorName
    Author name to treat as an error. Defaults to git config user.name in -RepoRoot.

.PARAMETER Term
    Additional private terms, such as hostnames or device names, to treat as errors. Keep the
    values out of tracked files; pass them at run time.

.PARAMETER IgnoreName
    Repository names that collide with ordinary technical terms, such as a repository named after a
    library it uses, to leave unmatched.

.PARAMETER IncludeForks
    Also match forks. Forks carry upstream project names, so they are skipped by default.

.PARAMETER IncludeAmbiguous
    Also match single-word repository names without the owner prefix, case-sensitively.

.PARAMETER FailOnError
    Exit with code 1 when any error-severity finding remains.

.EXAMPLE
    pwsh .github/skills/repository-privacy/scripts/Find-SpecificReferences.ps1
    Scans the shared guidance files of this repository against the authenticated user's repositories.

.EXAMPLE
    pwsh .github/skills/repository-privacy/scripts/Find-SpecificReferences.ps1 -RepoRoot <repo> -Exclude '*/tests/*','*/policies/*' -FailOnError
    Gates a commit, skipping test fixtures and owner policy data.

.NOTES
    Requires git, and gh authenticated as the owner unless -Repository and -Owner are supplied.
    Output names private repositories; keep it local.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../')),
    [string[]]$Path = @('.github/copilot-instructions.md', '.github/instructions', '.github/skills', '.github/prompts', '.github/agents'),
    [string[]]$Exclude = @('*/tests/*'),
    [string]$Owner,
    [object[]]$Repository,
    [string]$AuthorName,
    [string[]]$Term = @(),
    [string[]]$IgnoreName = @(),
    [switch]$IncludeForks,
    [switch]$IncludeAmbiguous,
    [switch]$FailOnError
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

#region Functions

$script:ExampleWording = [regex]'(?i)\b(?:for example|e\.g\.|such as|example (?:librar|repositor|implementation|package)|real-world example)'
$script:RealWorldHeading = [regex]'(?i)^(#{1,6})\s+.*real-world example'
$script:Heading = [regex]'^(#{1,6})\s'

function Get-ReferenceSeed {
    <#
    .SYNOPSIS
        Builds the matchers for owner, repository, author and term references.
    .PARAMETER Owner
        GitHub owner login.
    .PARAMETER Repository
        Objects with Name, Visibility and optional IsFork.
    .PARAMETER SelfRepository
        Name of the scanned repository, whose references are ignored.
    .PARAMETER AuthorName
        Author name to treat as an error.
    .PARAMETER Term
        Additional private terms.
    .PARAMETER IgnoreName
        Repository names to leave unmatched.
    .PARAMETER IncludeForks
        Match forks, whose names are upstream project names.
    .PARAMETER IncludeAmbiguous
        Match single-word repository names without the owner prefix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [object[]]$Repository = @(),
        [string]$SelfRepository,
        [string]$AuthorName,
        [string[]]$Term = @(),
        [string[]]$IgnoreName = @(),
        [switch]$IncludeForks,
        [switch]$IncludeAmbiguous
    )

    $ownerPattern = [regex]::Escape($Owner)
    $seeds = [System.Collections.Generic.List[object]]::new()

    foreach ($repo in @($Repository)) {
        $name = [string]$repo.Name
        if ($name.Length -lt 3 -or $name -in $IgnoreName) { continue }
        if (-not $IncludeForks -and $repo.PSObject.Properties.Name -contains 'IsFork' -and $repo.IsFork) { continue }
        $isAmbiguous = $name -cmatch '^(?:[a-z0-9]+|[A-Z0-9]+)$'
        $escaped = [regex]::Escape($name)
        $ownerOnly = $name.StartsWith('.') -or ($isAmbiguous -and -not $IncludeAmbiguous)
        $body = if ($ownerOnly) { "$ownerPattern/$escaped" } else { "(?:$ownerPattern/)?$escaped" }
        $options = if ($isAmbiguous -and -not $ownerOnly) { 'None' } else { 'IgnoreCase' }
        $isSelf = $SelfRepository -and $name -eq $SelfRepository
        $isPrivate = ([string]$repo.Visibility) -ne 'PUBLIC'
        $seeds.Add([pscustomobject]@{
                Value    = $name
                Kind     = if ($isSelf) { 'Self' } elseif ($isPrivate) { 'PrivateRepository' } else { 'PublicRepository' }
                Severity = if ($isSelf) { 'Ignore' } elseif ($isPrivate) { 'Error' } else { 'Review' }
                Regex    = [regex]::new("(?<![\w.-])$body(?![\w-])", $options)
            })
    }

    $seeds.Add([pscustomobject]@{
            Value    = $Owner
            Kind     = 'Owner'
            Severity = 'Review'
            Regex    = [regex]::new("(?<![\w.-])$ownerPattern(?![\w-])", 'IgnoreCase')
        })

    foreach ($value in @(@($AuthorName) + @($Term) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $seeds.Add([pscustomobject]@{
                Value    = $value
                Kind     = if ($value -eq $AuthorName) { 'AuthorName' } else { 'Term' }
                Severity = 'Error'
                Regex    = [regex]::new("(?<![\w])$([regex]::Escape($value))(?![\w])", 'IgnoreCase')
            })
    }

    return , $seeds.ToArray()
}

function Find-SpecificReference {
    <#
    .SYNOPSIS
        Returns error and review findings for the given files.
    .PARAMETER RepoRoot
        Repository root the file paths are relative to.
    .PARAMETER File
        Repository-relative file paths with / separators.
    .PARAMETER Seed
        Matchers from Get-ReferenceSeed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string[]]$File = @(),
        [Parameter(Mandatory = $true)][object[]]$Seed
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in $File) {
        $fullPath = Join-Path $RepoRoot $relative
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }

        $fileIsExample = $relative -match '(?i)real-world-example|(?:^|/)(?:examples|templates)/'
        $lines = @(Get-Content -LiteralPath $fullPath)
        $realWorldLevel = 0
        $introduced = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = [string]$lines[$index]
            $heading = $script:Heading.Match($line)
            if ($heading.Success) {
                $level = $heading.Groups[1].Value.Length
                $realWorld = $script:RealWorldHeading.Match($line)
                if ($realWorld.Success) { $realWorldLevel = $level }
                elseif ($realWorldLevel -gt 0 -and $level -le $realWorldLevel) { $realWorldLevel = 0 }
            }

            $hits = [System.Collections.Generic.List[object]]::new()
            foreach ($candidate in $Seed) {
                foreach ($match in $candidate.Regex.Matches($line)) {
                    $hits.Add([pscustomobject]@{ Seed = $candidate; Start = $match.Index; End = $match.Index + $match.Length })
                }
            }

            $previous = if ($index -gt 0) { [string]$lines[$index - 1] } else { '' }
            $hasExampleWording = $script:ExampleWording.IsMatch($line) -or $script:ExampleWording.IsMatch($previous)
            $isExample = $fileIsExample -or $realWorldLevel -gt 0 -or $hasExampleWording

            foreach ($match in $hits) {
                $isContained = @($hits | Where-Object {
                        $_ -ne $match -and $_.Start -le $match.Start -and $_.End -ge $match.End -and
                        ($_.End - $_.Start) -gt ($match.End - $match.Start)
                    }).Count -gt 0
                if ($isContained) { continue }

                $severity = $match.Seed.Severity
                if ($severity -eq 'Review' -and $hasExampleWording) { [void]$introduced.Add($match.Seed.Value) }
                $isAccepted = $isExample -or $introduced.Contains($match.Seed.Value)
                if ($severity -eq 'Ignore' -or ($severity -eq 'Review' -and $isAccepted)) { continue }

                $findings.Add([pscustomobject]@{
                        Severity = $severity
                        Kind     = $match.Seed.Kind
                        Value    = $match.Seed.Value
                        File     = $relative
                        Line     = $index + 1
                    })
            }
        }
    }

    return , $findings.ToArray()
}

function Get-ScannedFile {
    <#
    .SYNOPSIS
        Lists tracked files under the given paths, minus excluded patterns.
    .PARAMETER RepoRoot
        Repository root.
    .PARAMETER Path
        Repository-relative paths.
    .PARAMETER Exclude
        Wildcard patterns to skip.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string[]]$Path = @('.github/copilot-instructions.md', '.github/instructions', '.github/skills', '.github/prompts', '.github/agents'),
        [string[]]$Exclude = @()
    )

    $tracked = @(& git -C $RepoRoot ls-files -- @($Path))
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in '$RepoRoot'; pass a Git repository with -RepoRoot." }
    return , @($tracked | Where-Object {
            $file = $_
            @($Exclude | Where-Object { $file -like $_ }).Count -eq 0
        })
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Path = @($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
        $Exclude = @($Exclude | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
        $Term = @($Term | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
        $IgnoreName = @($IgnoreName | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
        if (-not $Owner) {
            $Owner = (& gh api user -q .login)
            if ($LASTEXITCODE -ne 0 -or -not $Owner) { throw 'Could not resolve the owner; authenticate gh or pass -Owner.' }
        }
        if (-not $PSBoundParameters.ContainsKey('Repository')) {
            $json = & gh repo list $Owner --limit 1000 --json name,visibility,isFork
            if ($LASTEXITCODE -ne 0) { throw "Could not list repositories for '$Owner'; pass -Repository instead." }
            $Repository = @($json | ConvertFrom-Json | ForEach-Object { [pscustomobject]@{ Name = $_.name; Visibility = $_.visibility; IsFork = $_.isFork } })
        }
        if (-not $PSBoundParameters.ContainsKey('AuthorName')) {
            $AuthorName = (& git -C $RepoRoot config user.name)
        }

        $selfRepository = $null
        $origin = & git -C $RepoRoot remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and $origin -match '[/:]([^/]+?)(?:\.git)?$') { $selfRepository = $Matches[1] }

        $seeds = Get-ReferenceSeed -Owner $Owner -Repository $Repository -SelfRepository $selfRepository `
            -AuthorName $AuthorName -Term $Term -IgnoreName $IgnoreName -IncludeForks:$IncludeForks `
            -IncludeAmbiguous:$IncludeAmbiguous
        $files = Get-ScannedFile -RepoRoot $RepoRoot -Path $Path -Exclude $Exclude
        $findings = Find-SpecificReference -RepoRoot $RepoRoot -File $files -Seed $seeds

        if ($findings.Count -eq 0) {
            Write-Host "No specific references found in $($files.Count) file(s)."
        }
        else {
            $findings | Sort-Object Severity, File, Line | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
            $errorCount = @($findings | Where-Object Severity -eq 'Error').Count
            Write-Host "Errors: $errorCount  Review: $($findings.Count - $errorCount)  Files: $($files.Count)"
        }

        if ($FailOnError -and @($findings | Where-Object Severity -eq 'Error').Count -gt 0) { exit 1 }
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Specific-reference scan failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
