#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Scans a repository for personally identifiable information (PII) and other
    private values that should never be committed.

.DESCRIPTION
    PII detection works in two complementary ways:

      1. Seeded literals - the script reads the *gitignored* Local configuration files
         (appsettings.Local.json, appsettings.Local.Development.json, .env) which hold the
         real production/development secrets, and extracts concrete values from them
         (private domains, phone numbers, RFC1918 IP addresses, Azure storage-account
         names, Key Vault names, tenant IDs, Windows user paths). These exact values are
         then searched for across the repo. Because the seeds are read at runtime, no real
         PII is ever hardcoded into this (committed) script.

      2. Generic heuristics - always-on regular expressions catch PII shapes even when a
         value is not present in the Local files (emails, E.164 phone numbers, private
         IPv4 ranges, *.{blob,table,queue,file}.core.windows.net accounts, user paths).

    Both the current working tree (tracked files only) and, optionally, the entire git
    history are searched. Known-safe placeholder values (example.com, 192.168.1.100,
    devstoreaccount1, the public Azurite key, the empty GUID, +10000000000, demo, ...)
    are filtered out of the results.

.PARAMETER RepoRoot
    Repository root. Defaults to the parent of the folder containing this script.

.PARAMETER SeedFile
    Files to extract real PII seed values from. Defaults to the gitignored Local config
    files plus .env. Missing files are skipped silently.

.PARAMETER IncludeHistory
    Also scan every commit reachable from all refs (git rev-list --all). Slower, but this
    is what finds PII that was committed and later removed from the working tree.

.PARAMETER OutFile
    Optional path to write the full result set as CSV.

.PARAMETER FailOnFind
    Exit with code 1 if any high-confidence seeded match is found (useful for pre-commit / CI).

.EXAMPLE
    pwsh .scripts/Find-Pii.ps1
    Scan the working tree using seeds from the Local config files.

.EXAMPLE
    pwsh .scripts/Find-Pii.ps1 -IncludeHistory
    Scan the working tree AND the entire git history. Use this to find PII that was
    committed and later removed from the working tree (still recoverable from history).

.EXAMPLE
    pwsh .scripts/Find-Pii.ps1 -IncludeHistory -OutFile pii-report.csv
    Scan the working tree and full history, writing a CSV report.
    NOTE: the CSV contains the real PII values - it is gitignored (pii-report*.csv) and
    must never be committed.

.EXAMPLE
    pwsh .scripts/Find-Pii.ps1 -FailOnFind
    Scan and exit 1 if any high-confidence (seed) PII is found. Use in pre-commit hooks
    and CI to block leaks before they are committed.

.NOTES
    ============================ HOW TO USE ============================

    This script is maintained centrally and is repository-agnostic. Run it against any
    repository by passing -RepoRoot; it reads its seed values at runtime, so it contains
    no hardcoded PII and needs no per-repository edits.

      # Run BEFORE every local git commit (working-tree scan):
      pwsh ./.scripts/Find-Pii.ps1 -RepoRoot <path-to-repo>

      # Block the commit if real PII is present (recommended pre-commit gate):
      pwsh ./.scripts/Find-Pii.ps1 -RepoRoot <path-to-repo> -FailOnFind

      # Audit the full history (slow) and export a CSV for review:
      pwsh ./.scripts/Find-Pii.ps1 -RepoRoot <path-to-repo> -IncludeHistory -OutFile pii-report.csv

    Pre-commit reminder: ALWAYS run this script (or have the agent run it) before any
    local `git commit` in a PUBLIC repository. Git-tracked configuration must contain only
    placeholders; real values live exclusively in gitignored local configuration files.

    ===================== PER-REPOSITORY TUNING =====================

      1. Add the report artifact to the scanned repository's .gitignore:
             pii-report*.csv
      2. Adjust -SeedFile if that repository's gitignored secret files differ (for example a
         repository without .env, or with extra *.Local.* files).
      3. Review the $publicApex and allowlist arrays below and add any public domains or
         placeholder values that would otherwise be reported as false positives.
      4. (Optional) Wire a -FailOnFind invocation into that repository's pre-commit
         configuration or a CI job.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string[]]$SeedFile = @(
        'appsettings.Local.json',
        'appsettings.Local.Development.json',
        '.env'
    ),
    [switch]$IncludeHistory,
    [string]$OutFile,
    [switch]$FailOnFind
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

#region Functions

function Invoke-PiiScan {
    <#
    .SYNOPSIS
        Scans a repository and returns its PII findings.
    .PARAMETER RepoRoot
        Repository root to scan.
    .PARAMETER SeedFile
        Repository-relative files from which exact seed values are extracted.
    .PARAMETER IncludeHistory
        Scans all reachable commits in addition to the working tree.
    .PARAMETER OutFile
        Optional CSV output path.
    .OUTPUTS
        PSCustomObject containing seeds, findings, and the high-confidence hit count.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$SeedFile,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeHistory,

        [Parameter(Mandatory = $false)]
        [string]$OutFile
    )

    if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
        throw "RepoRoot '$RepoRoot' does not look like a git repository (no .git found)."
    }
    Push-Location $RepoRoot
    try {
    # ----------------------------------------------------------------------------------
    # Allowlist - values that are intentionally generic placeholders and are NOT PII.
    # A candidate match is dropped if its matched value equals (case-insensitive) any of
    # these, or matches one of the allowlist regexes.
    # ----------------------------------------------------------------------------------
    $allowLiterals = @(
        'example.com', 'example.net', 'example.org',
        'localhost', 'cluster.local', 'svc.cluster.local',
        '127.0.0.1', '0.0.0.0', '255.255.255.255', '192.168.1.100', '192.168.1.255',
        'devstoreaccount1', 'mystorageaccount',
        '+10000000000',
        '00000000-0000-0000-0000-000000000000',
        'demo', 'skip',
        # Public, well-known Azurite development storage key - safe to commit.
        'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=='
    )
    $allowRegex = @(
        [regex]'(?i)\.(blob|table|queue|file)\.core\.windows\.net$' # the bare suffix with no account
    )

    # Public apex domains that must NOT be treated as private when extracting domain seeds.
    $publicApex = @(
        'windows.net', 'core.windows.net', 'microsoft.com', 'azure.com', 'visualstudio.com',
        'github.com', 'githubusercontent.com', 'nuget.org', 'w3.org', 'schemas.microsoft.com',
        'cluster.local', 'svc.cluster.local', 'localhost', 'shelly.cloud', 'thingscloud.it',
        'gravatar.com', 'googleapis.com', 'gstatic.com', 'miele.com', 'example.com', 'example.net', 'example.org'
    ) | ForEach-Object { $_.ToLowerInvariant() }

    function Test-Allowlisted {
        param([string]$Value)
        $v = $Value.Trim()
        foreach ($lit in $allowLiterals) {
            if ($v -ieq $lit) { return $true }
        }
        foreach ($rx in $allowRegex) {
            if ($rx.IsMatch($v)) { return $true }
        }
        return $false
    }

    # ----------------------------------------------------------------------------------
    # 1. Extract real seed values from the gitignored Local config files.
    # ----------------------------------------------------------------------------------
    $seedValues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $rxPhone = [regex]'\+[1-9]\d{7,14}'
    $rxRfc1918 = [regex]'\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b'
    $rxStorage = [regex]'(?i)\b([a-z0-9]{3,24})\.(?:blob|table|queue|file)\.core\.windows\.net\b'
    $rxTenant = [regex]'(?i)"(?:AzureEntraTenantId|TenantId)"\s*:\s*"([0-9a-f-]{36})"'
    # Only treat a host as a private-domain seed when it appears in a real URL/connection
    # context - this avoids mis-reading dotted code identifiers (Contoso.App.Server,
    # Microsoft.AspNetCore, instructions.md, ...) as domains.
    $rxUrlHost = [regex]'(?i)\b(?:https?|wss?|redis|amqps?|mongodb|tcp|grpc)://([a-z0-9.\-]+)'

    function Get-Apex {
        param([string]$Hostname)
        $labels = $Hostname.ToLowerInvariant().TrimEnd('.').Split('.')
        if ($labels.Count -lt 2) { return $null }
        return ($labels[-2] + '.' + $labels[-1])
    }

    $seedFilesFound = @()
    foreach ($sf in $SeedFile) {
        $path = Join-Path $RepoRoot $sf
        if (-not (Test-Path $path)) { continue }
        $seedFilesFound += $sf
        $text = Get-Content -LiteralPath $path -Raw

        # Private domains - apex of any host that appears inside a URL/connection string.
        foreach ($m in $rxUrlHost.Matches($text)) {
            $hn = $m.Groups[1].Value
            # Skip IP-address hosts (handled by the IP matcher) and hosts with a non-alpha TLD.
            if ($hn -match '^\d{1,3}(\.\d{1,3}){3}$') { continue }
            $apex = Get-Apex $hn
            if ($null -eq $apex) { continue }
            if ($apex -notmatch '\.[a-z]{2,}$') { continue }
            if ($publicApex -contains $apex) { continue }
            [void]$seedValues.Add($apex)
        }
        # Phone numbers.
        foreach ($m in $rxPhone.Matches($text)) { [void]$seedValues.Add($m.Value) }
        # RFC1918 IPs.
        foreach ($m in $rxRfc1918.Matches($text)) { [void]$seedValues.Add($m.Value) }
        # Azure storage account names.
        foreach ($m in $rxStorage.Matches($text)) { [void]$seedValues.Add($m.Groups[1].Value) }
        # Tenant IDs.
        foreach ($m in $rxTenant.Matches($text)) { [void]$seedValues.Add($m.Groups[1].Value) }
    }

    # Drop allowlisted / too-short seeds.
    $seeds = @($seedValues | Where-Object { $_.Length -ge 3 -and -not (Test-Allowlisted $_) } | Sort-Object)

    Write-Host "Seed files used:   $([string]::Join(', ', $seedFilesFound))" -ForegroundColor Cyan
    Write-Host "Seed values found: $($seeds.Count)" -ForegroundColor Cyan

    # ----------------------------------------------------------------------------------
    # 2. Precise matchers used to classify candidate lines (name -> regex).
    # ----------------------------------------------------------------------------------
    $matchers = [ordered]@{
        'Email'        = [regex]'(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
        'Phone'        = $rxPhone
        'PrivateIPv4'  = $rxRfc1918
        'AzureStorage' = $rxStorage
        'UserPath'     = [regex]'(?i)[a-z]:\\Users\\[^\\/"<>:|?*\s]+'
    }
    foreach ($s in $seeds) {
        $escapedSeed = [regex]::Escape($s)
        $matchers["Seed:$s"] = if ($s -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
            [regex]("(?i)(?<![0-9.])$escapedSeed(?![0-9.])")
        }
        else {
            [regex]("(?i)$escapedSeed")
        }
    }

    # ----------------------------------------------------------------------------------
    # 3. Build git-grep prefilter arguments.
    #    -E generic patterns + -F literal seeds. Two passes, results merged.
    # ----------------------------------------------------------------------------------
    $erePatterns = @(
        '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
        '\+[1-9][0-9]{7,14}',
        '\b(10(\.[0-9]{1,3}){3}|192\.168(\.[0-9]{1,3}){2}|172\.(1[6-9]|2[0-9]|3[01])(\.[0-9]{1,3}){2})\b',
        '[A-Za-z0-9]{3,24}\.(blob|table|queue|file)\.core\.windows\.net',
        '[/\\]Users[/\\]'
    )

    # Pathspecs to exclude the seed files themselves and obvious binaries.
    $excludePaths = @(
        ":(exclude)appsettings.Local.json",
        ":(exclude)appsettings.Local.*.json",
        ":(exclude).env",
        ":(exclude)*.png", ":(exclude)*.jpg", ":(exclude)*.jpeg", ":(exclude)*.gif",
        ":(exclude)*.ico", ":(exclude)*.pfx", ":(exclude)*.dll", ":(exclude)*.exe"
    )

    function Invoke-GitGrep {
        param(
            [string[]]$TreeIsh = @() # empty = working tree
        )
        $lines = [System.Collections.Generic.List[string]]::new()

        # Pass A: extended-regex generic patterns.
        $argsA = @('grep', '-n', '-I', '--no-color', '-i', '-E')
        foreach ($p in $erePatterns) { $argsA += @('-e', $p) }
        $argsA += $TreeIsh
        $argsA += '--'
        $argsA += $excludePaths
        $outA = @(& git @argsA 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -notin @(0, 1)) {
            throw "git grep failed with exit code ${exitCode}: $($outA -join [Environment]::NewLine)"
        }
        if ($outA) { $outA | ForEach-Object { $lines.Add($_) } }

        # Pass B: fixed-string literal seeds.
        if ($seeds.Count -gt 0) {
            $argsB = @('grep', '-n', '-I', '--no-color', '-i', '-F')
            foreach ($s in $seeds) { $argsB += @('-e', $s) }
            $argsB += $TreeIsh
            $argsB += '--'
            $argsB += $excludePaths
            $outB = @(& git @argsB 2>&1)
            $exitCode = $LASTEXITCODE
            if ($exitCode -notin @(0, 1)) {
                throw "git grep failed with exit code ${exitCode}: $($outB -join [Environment]::NewLine)"
            }
            if ($outB) { $outB | ForEach-Object { $lines.Add($_) } }
        }

        return $lines
    }

    # ----------------------------------------------------------------------------------
    # 4. Classify a raw "content" string into precise matches, dropping allowlisted ones.
    # ----------------------------------------------------------------------------------
    function Get-Matches {
        param([string]$Content)
        $results = @()
        foreach ($name in $matchers.Keys) {
            foreach ($m in $matchers[$name].Matches($Content)) {
                $val = $m.Value
                if (Test-Allowlisted $val) { continue }
                $confidence = if ($name -like 'Seed:*') { 'seed' } else { 'heuristic' }
                $results += [pscustomobject]@{ Pattern = $name; Value = $val; Confidence = $confidence }
            }
        }
        return $results
    }

    $findings = [System.Collections.Generic.List[object]]::new()

    # ---- Working tree ----------------------------------------------------------------
    Write-Host "`nScanning working tree..." -ForegroundColor Yellow
    $rxWork = [regex]'^(.*?):(\d+):(.*)$'
    foreach ($line in (Invoke-GitGrep)) {
        $mm = $rxWork.Match($line)
        if (-not $mm.Success) { continue }
        $file = $mm.Groups[1].Value
        $ln = [int]$mm.Groups[2].Value
        $content = $mm.Groups[3].Value
        foreach ($hit in (Get-Matches $content)) {
            $findings.Add([pscustomobject]@{
                    Source     = 'working-tree'
                    Commit     = ''
                    File       = $file
                    Line       = $ln
                    Pattern    = $hit.Pattern
                    Value      = $hit.Value
                    Confidence = $hit.Confidence
                    Text       = $content.Trim()
                })
        }
    }

    # ---- History ---------------------------------------------------------------------
    if ($IncludeHistory) {
        Write-Host "Scanning full git history (this can take a while)..." -ForegroundColor Yellow
        $commits = @(& git rev-list --all 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "git rev-list failed with exit code ${LASTEXITCODE}: $($commits -join [Environment]::NewLine)"
        }
        Write-Host "  commits to scan: $($commits.Count)" -ForegroundColor DarkGray
        $rxHist = [regex]'^([0-9a-f]{7,40}):(.*?):(\d+):(.*)$'
        $batchSize = 150
        for ($i = 0; $i -lt $commits.Count; $i += $batchSize) {
            $batch = $commits[$i..([Math]::Min($i + $batchSize - 1, $commits.Count - 1))]
            Write-Progress -Activity 'Scanning history' -Status "commit $i / $($commits.Count)" `
                -PercentComplete (($i / [Math]::Max($commits.Count, 1)) * 100)
            foreach ($line in (Invoke-GitGrep -TreeIsh $batch)) {
                $mm = $rxHist.Match($line)
                if (-not $mm.Success) { continue }
                $commit = $mm.Groups[1].Value
                $file = $mm.Groups[2].Value
                $ln = [int]$mm.Groups[3].Value
                $content = $mm.Groups[4].Value
                foreach ($hit in (Get-Matches $content)) {
                    $findings.Add([pscustomobject]@{
                            Source     = 'history'
                            Commit     = $commit.Substring(0, 10)
                            File       = $file
                            Line       = $ln
                            Pattern    = $hit.Pattern
                            Value      = $hit.Value
                            Confidence = $hit.Confidence
                            Text       = $content.Trim()
                        })
                }
            }
        }
        Write-Progress -Activity 'Scanning history' -Completed
    }

    # ----------------------------------------------------------------------------------
    # 5. Report.
    # ----------------------------------------------------------------------------------
    Write-Host "`n================ PII SCAN SUMMARY ================" -ForegroundColor Green

    function Write-Group {
        param([object[]]$Items, [string]$Heading, [ConsoleColor]$Color)
        Write-Host "`n$Heading ($($Items.Count) match(es))" -ForegroundColor $Color
        if ($Items.Count -eq 0) { return }
        $Items |
        Group-Object Value |
        Sort-Object Count -Descending |
        ForEach-Object {
            $files = @($_.Group | Select-Object -ExpandProperty File -Unique)
            $shown = ($files | Select-Object -First 6) -join ', '
            if ($files.Count -gt 6) { $shown += ", (+$($files.Count - 6) more)" }
            Write-Host ("  {0,-38} x{1,-4} {2}" -f $_.Name, $_.Count, $shown)
        }
    }

    $workFindings = @($findings | Where-Object Source -eq 'working-tree')
    Write-Host "`n----- WORKING TREE -----" -ForegroundColor Green
    Write-Group -Items @($workFindings | Where-Object Confidence -eq 'seed') `
        -Heading 'HIGH CONFIDENCE (real values from Local config)' -Color Red
    Write-Group -Items @($workFindings | Where-Object Confidence -eq 'heuristic') `
        -Heading 'HEURISTIC (generic patterns - review)' -Color Yellow

    if ($IncludeHistory) {
        $histFindings = @($findings | Where-Object Source -eq 'history')
        Write-Host "`n----- GIT HISTORY -----" -ForegroundColor Green
        $histSeed = @($histFindings | Where-Object Confidence -eq 'seed')
        Write-Host "`nHIGH CONFIDENCE (real values from Local config) ($($histSeed.Count) match(es))" -ForegroundColor Red
        if ($histSeed.Count -gt 0) {
            $histSeed |
            Group-Object Value |
            Sort-Object Count -Descending |
            ForEach-Object {
                $commits = @($_.Group | Select-Object -ExpandProperty Commit -Unique)
                $shown = ($commits | Select-Object -First 8) -join ', '
                if ($commits.Count -gt 8) { $shown += ", (+$($commits.Count - 8) more)" }
                Write-Host ("  {0,-38} x{1,-4} in {2} commit(s): {3}" -f $_.Name, $_.Count, $commits.Count, $shown)
            }
        }
        $histHeur = @($histFindings | Where-Object Confidence -eq 'heuristic')
        Write-Host "`nHEURISTIC (generic patterns - review) ($($histHeur.Count) match(es))" -ForegroundColor Yellow
        if ($histHeur.Count -gt 0) {
            $histHeur |
            Group-Object Value |
            Sort-Object Count -Descending |
            Select-Object -First 30 |
            ForEach-Object {
                $commits = @($_.Group | Select-Object -ExpandProperty Commit -Unique)
                Write-Host ("  {0,-38} x{1,-4} in {2} commit(s)" -f $_.Name, $_.Count, $commits.Count)
            }
        }
    }

    if ($OutFile) {
        $findings | Sort-Object Source, Confidence, File, Line |
        Export-Csv -LiteralPath $OutFile -NoTypeInformation -Encoding utf8
        Write-Host "`nFull report written to: $OutFile" -ForegroundColor Cyan
    }

    $seedHits = @($findings | Where-Object Confidence -eq 'seed').Count
    Write-Host "`nTotal: $($findings.Count) match(es)  |  high-confidence (seed): $seedHits" -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Green

        return [pscustomobject]@{
            Seeds    = @($seeds)
            Findings = @($findings)
            SeedHits = $seedHits
        }
    }
    finally {
        Pop-Location
    }
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $Result = Invoke-PiiScan `
            -RepoRoot $RepoRoot `
            -SeedFile $SeedFile `
            -IncludeHistory:$IncludeHistory `
            -OutFile $OutFile
        if ($FailOnFind -and $Result.SeedHits -gt 0) {
            exit 1
        }
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "PII scan failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
