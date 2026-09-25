#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Audits Dockerfiles against the shared container image conventions.
.DESCRIPTION
    Parses each Dockerfile, including line continuations, heredocs, parser directives and stages,
    and reports the house rules that `docker buildx build --check` does not enforce. The image
    profile relaxes rules: it is read from a `# Profile: <name>` header comment, inferred as `debug`
    for files named `*.Debug`, and otherwise defaults to `published`. The workload shape is read from
    a `# Shape: <service|job|tool>` header comment and defaults to `service`.

    Rules about the published image follow `FROM <stage>` inheritance, so a `final` stage derived
    from a shared runtime stage inherits its USER, ENTRYPOINT, ARG and LABEL instructions.

    Directories are searched recursively. `.git`, `.devcontainer`, `node_modules`, `bin`, `obj`,
    `target` and `deps` are skipped: dev container Dockerfiles are owned by the devcontainer skill,
    and `deps` holds mirrored sibling repositories.
.PARAMETER Path
    Dockerfiles or directories to audit. Defaults to the current directory.
.PARAMETER ImageProfile
    Overrides the detected profile: published, single-arch, vendor, debug or sample.
.PARAMETER ContextPath
    Build context directory used to locate `.dockerignore`. Defaults to the nearest ancestor
    containing `.git`, or the Dockerfile's own directory.
.PARAMETER Skip
    Rule identifiers to suppress, for example DF018.
.PARAMETER FailOn
    Lowest severity that produces exit code 2: error (default), warning or never.
.EXAMPLE
    ./Test-Dockerfile.ps1 -Path ./Dockerfile
.EXAMPLE
    ./Test-Dockerfile.ps1 -Path ~/source/example -FailOn warning | Format-Table
.NOTES
    Exit codes: 0 no blocking findings, 2 blocking findings, 1 the audit itself failed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Path = @('.'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('auto', 'published', 'single-arch', 'vendor', 'debug', 'sample')]
    [string]$ImageProfile = 'auto',

    [Parameter(Mandatory = $false)]
    [string]$ContextPath,

    [Parameter(Mandatory = $false)]
    [string[]]$Skip = @(),

    [Parameter(Mandatory = $false)]
    [ValidateSet('error', 'warning', 'never')]
    [string]$FailOn = 'error'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

#region Rules

$script:RelaxedRules = @{
    'single-arch' = @('DF003', 'DF004')
    'vendor'      = @('DF004', 'DF014')
    'debug'       = @('DF013', 'DF014', 'DF015')
}
$script:SampleRules = @('DF002', 'DF005', 'DF017', 'DF022')
$script:ProvenanceArgs = @('GIT_REPOSITORY', 'GIT_BRANCH', 'GIT_COMMIT', 'GIT_TAG', 'GITHUB_WORKFLOW', 'GITHUB_RUN_ID', 'GITHUB_RUN_NUMBER')
$script:OciLabelKeys = @('title', 'description', 'source', 'licenses', 'version', 'revision')
$script:ExcludedDirectories = @('.git', '.devcontainer', 'node_modules', 'bin', 'obj', 'target', 'deps')
$script:Keywords = 'FROM|RUN|COPY|ADD|ENV|ARG|ENTRYPOINT|CMD|USER|WORKDIR|EXPOSE|LABEL|VOLUME|HEALTHCHECK|SHELL|ONBUILD|STOPSIGNAL'

function Test-RuleEnabled {
    <#
    .SYNOPSIS
        Returns whether a rule applies to an image profile.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$Rule,
        [Parameter(Mandatory = $true)][string]$ImageProfile
    )

    if ($ImageProfile -eq 'sample') {
        return $Rule -in $script:SampleRules
    }

    if ($script:RelaxedRules.ContainsKey($ImageProfile)) {
        return $Rule -notin $script:RelaxedRules[$ImageProfile]
    }

    return $true
}

#endregion

#region Parsing

function ConvertFrom-KeyValueArgument {
    <#
    .SYNOPSIS
        Splits ARG, ENV or LABEL arguments into name and value pairs. A missing value is $null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Arguments
    )

    $trimmed = $Arguments.Trim()
    if ($trimmed -eq '') {
        return
    }

    if ($trimmed -notmatch '=' -or $trimmed -match '^[A-Za-z_][A-Za-z0-9_.-]*\s+[^=]*$') {
        $first, $rest = $trimmed -split '\s+', 2
        [pscustomobject]@{ Name = $first; Value = $(if ($rest) { $rest } else { $null }) }
        return
    }

    $pattern = '([A-Za-z_][A-Za-z0-9_.-]*)(?:=("[^"]*"|''[^'']*''|\S*))?'
    foreach ($match in [regex]::Matches($trimmed, $pattern)) {
        $value = if ($match.Groups[2].Success) { $match.Groups[2].Value.Trim('"', "'") } else { $null }
        [pscustomobject]@{ Name = $match.Groups[1].Value; Value = $value }
    }
}

function Resolve-DockerfileVariable {
    <#
    .SYNOPSIS
        Substitutes $NAME and ${NAME} references with known global ARG defaults.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][hashtable]$Variables
    )

    $known = $Variables
    $evaluator = {
        param($match)
        $name = $match.Groups[1].Value + $match.Groups[3].Value
        if ($known.ContainsKey($name)) { $known[$name] } else { $match.Value }
    }.GetNewClosure()

    return [regex]::Replace($Value, '\$\{([A-Za-z_][A-Za-z0-9_]*)(:-[^}]*)?\}|\$([A-Za-z_][A-Za-z0-9_]*)', $evaluator)
}

function Read-DockerfileModel {
    <#
    .SYNOPSIS
        Parses Dockerfile lines into directives, comments, instructions and stages.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Line
    )

    $directives = @{}
    $header = [Collections.Generic.List[string]]::new()
    $comments = [Collections.Generic.List[pscustomobject]]::new()
    $instructions = [Collections.Generic.List[pscustomobject]]::new()
    $directivePhase = $true
    $index = 0

    while ($index -lt $Line.Count) {
        $trimmed = $Line[$index].Trim()

        if ($directivePhase) {
            if ($trimmed -match '^#\s*([A-Za-z]+)\s*=\s*(.+?)\s*$') {
                $directives[$Matches[1].ToLowerInvariant()] = $Matches[2]
                $index++
                continue
            }
            $directivePhase = $false
        }

        if ($trimmed -eq '') {
            $index++
            continue
        }

        if ($trimmed.StartsWith('#')) {
            $comments.Add([pscustomobject]@{ Line = $index + 1; Text = $trimmed })
            if ($instructions.Count -eq 0) {
                $header.Add($trimmed)
            }
            $index++
            continue
        }

        $start = $index
        $parts = [Collections.Generic.List[string]]::new()
        $current = $Line[$index]
        while ($current.TrimEnd().EndsWith('\') -and ($index + 1) -lt $Line.Count) {
            $withoutSlash = $current.TrimEnd()
            $parts.Add($withoutSlash.Substring(0, $withoutSlash.Length - 1))
            $index++
            $current = $Line[$index]
            while ($current.Trim().StartsWith('#') -and ($index + 1) -lt $Line.Count) {
                $index++
                $current = $Line[$index]
            }
        }
        $parts.Add($current)
        $index++

        $joined = (@($parts | ForEach-Object { $_.Trim() }) -join ' ').Trim()
        $heredocs = [Collections.Generic.List[string]]::new()
        foreach ($match in [regex]::Matches($joined, '<<(-?)(["'']?)([A-Za-z_][A-Za-z0-9_]*)\2')) {
            $stripTabs = $match.Groups[1].Value -eq '-'
            $delimiter = $match.Groups[3].Value
            $body = [Collections.Generic.List[string]]::new()
            while ($index -lt $Line.Count) {
                $candidate = $Line[$index]
                $index++
                $compare = if ($stripTabs) { $candidate.TrimStart("`t") } else { $candidate }
                if ($compare.TrimEnd() -eq $delimiter) {
                    break
                }
                $body.Add($candidate)
            }
            $heredocs.Add(($body -join "`n"))
        }

        if ($joined -match '^([A-Za-z]+)\s*(.*)$') {
            $instructions.Add([pscustomobject]@{
                    Line      = $start + 1
                    Keyword   = $Matches[1].ToUpperInvariant()
                    Arguments = $Matches[2]
                    Heredocs  = [string[]]$heredocs.ToArray()
                })
        }
    }

    $globalArgs = @{}
    $stages = [Collections.Generic.List[pscustomobject]]::new()
    foreach ($instruction in $instructions) {
        if ($instruction.Keyword -eq 'FROM') {
            $platform = $null
            $positional = [Collections.Generic.List[string]]::new()
            foreach ($token in @($instruction.Arguments -split '\s+' | Where-Object { $_ })) {
                if ($token -match '^--platform=(.+)$') {
                    $platform = $Matches[1]
                }
                elseif (-not $token.StartsWith('--')) {
                    $positional.Add($token)
                }
            }

            $image = if ($positional.Count -gt 0) { $positional[0] } else { '' }
            $stages.Add([pscustomobject]@{
                    Index        = $stages.Count
                    Line         = $instruction.Line
                    Image        = $image
                    Resolved     = (Resolve-DockerfileVariable -Value $image -Variables $globalArgs)
                    Name         = $(if ($positional.Count -ge 3 -and $positional[1] -ieq 'AS') { $positional[2] } else { $null })
                    Platform     = $platform
                    Instructions = [Collections.Generic.List[pscustomobject]]::new()
                })
        }
        elseif ($stages.Count -eq 0) {
            if ($instruction.Keyword -eq 'ARG') {
                foreach ($pair in @(ConvertFrom-KeyValueArgument -Arguments $instruction.Arguments)) {
                    if ($null -ne $pair.Value) {
                        $globalArgs[$pair.Name] = $pair.Value
                    }
                }
            }
        }
        else {
            $stages[$stages.Count - 1].Instructions.Add($instruction)
        }
    }

    [pscustomobject]@{
        Directives   = $directives
        Header       = [string[]]$header.ToArray()
        Comments     = [pscustomobject[]]$comments.ToArray()
        Instructions = [pscustomobject[]]$instructions.ToArray()
        Stages       = [pscustomobject[]]$stages.ToArray()
    }
}

function Resolve-ImageProfile {
    <#
    .SYNOPSIS
        Determines the image profile from the parameter, header comment or file name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][pscustomobject]$Model,
        [Parameter(Mandatory = $true)][string]$Requested
    )

    if ($Requested -ne 'auto') {
        return $Requested
    }

    foreach ($comment in $Model.Header) {
        if ($comment -match '^#\s*Profile:\s*(published|single-arch|vendor|debug|sample)\s*$') {
            return $Matches[1].ToLowerInvariant()
        }
    }

    if ([IO.Path]::GetFileName($FilePath) -match '\.Debug$') {
        return 'debug'
    }

    return 'published'
}

function Resolve-WorkloadShape {
    <#
    .SYNOPSIS
        Reads the workload shape from a `# Shape: <name>` header comment; defaults to service.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][pscustomobject]$Model)

    foreach ($comment in $Model.Header) {
        if ($comment -match '^#\s*Shape:\s*(service|job|tool)\s*$') {
            return $Matches[1].ToLowerInvariant()
        }
    }

    return 'service'
}

function Get-StageChain {
    <#
    .SYNOPSIS
        Returns a stage and every stage it derives from through `FROM <stage>`, base first.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Stage,
        [Parameter(Mandatory = $true)][pscustomobject[]]$Stages
    )

    $chain = [Collections.Generic.List[pscustomobject]]::new()
    $visited = [Collections.Generic.HashSet[int]]::new()
    $current = $Stage
    while ($null -ne $current -and $visited.Add([int]$current.Index)) {
        $chain.Insert(0, $current)
        $reference = $current.Resolved.ToLowerInvariant()
        $parent = @($Stages | Where-Object { $_.Name -and $_.Name.ToLowerInvariant() -eq $reference -and $_.Index -lt $current.Index } | Select-Object -Last 1)
        $current = if ($parent.Count -gt 0) { $parent[0] } else { $null }
    }

    $chain
}

#endregion

#region Audit

function ConvertTo-Finding {
    <#
    .SYNOPSIS
        Creates an unscoped finding record.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][int]$Line,
        [Parameter(Mandatory = $true)][string]$Rule,
        [Parameter(Mandatory = $true)][ValidateSet('error', 'warning')][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message
    )

    [pscustomobject]@{ Line = $Line; Rule = $Rule; Severity = $Severity; Message = $Message }
}

function Test-DockerIgnore {
    <#
    .SYNOPSIS
        Checks that the build context has an allow-list .dockerignore.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $false)][string]$ContextPath
    )

    $context = $ContextPath
    if ([string]::IsNullOrWhiteSpace($context)) {
        $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($FilePath))
        $context = $directory
        $probe = $directory
        while ($probe) {
            if (Test-Path -LiteralPath (Join-Path $probe '.git')) {
                $context = $probe
                break
            }
            $probe = [IO.Path]::GetDirectoryName($probe)
        }
    }

    $specific = "$FilePath.dockerignore"
    $ignoreFile = if (Test-Path -LiteralPath $specific) { $specific } else { Join-Path $context '.dockerignore' }
    if (-not (Test-Path -LiteralPath $ignoreFile)) {
        ConvertTo-Finding 0 'DF019' 'error' "No .dockerignore found for build context '$context'."
        return
    }

    $first = @(Get-Content -LiteralPath $ignoreFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1)
    if ($first.Count -eq 0 -or $first[0] -notin @('*', '**', '/*', '/**')) {
        ConvertTo-Finding 0 'DF020' 'error' "'$([IO.Path]::GetFileName($ignoreFile))' is not an allow-list; its first pattern must be '*'."
    }
}

function Get-RawFinding {
    <#
    .SYNOPSIS
        Applies every rule to a parsed Dockerfile, before profile filtering.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Model,
        [Parameter(Mandatory = $false)][string]$Shape = 'service'
    )

    if (-not $Model.Directives.ContainsKey('syntax')) {
        ConvertTo-Finding 1 'DF001' 'error' 'Missing parser directive `# syntax=docker/dockerfile:1` on the first line.'
    }
    elseif ($Model.Directives['syntax'] -ne 'docker/dockerfile:1') {
        ConvertTo-Finding 1 'DF001' 'warning' "Syntax directive is '$($Model.Directives['syntax'])'; use 'docker/dockerfile:1'."
    }

    $stages = @($Model.Stages)
    if ($stages.Count -eq 0) {
        ConvertTo-Finding 1 'DF023' 'error' 'No FROM instruction found.'
        return
    }

    $stageNames = @($stages | Where-Object { $_.Name } | ForEach-Object { $_.Name.ToLowerInvariant() })
    $final = $stages[$stages.Count - 1]
    $finalChain = @(Get-StageChain -Stage $final -Stages $stages)
    $finalChainIndexes = @($finalChain | ForEach-Object { $_.Index })
    $finalInstructions = @($finalChain | ForEach-Object { $_.Instructions })

    foreach ($stage in $stages) {
        $image = $stage.Resolved
        $isStageReference = $image.ToLowerInvariant() -in $stageNames
        if (-not $isStageReference -and $image -ne 'scratch' -and $image -notmatch '\$') {
            $lastSegment = (($image -split '@', 2)[0] -split '/')[-1]
            if (-not $image.Contains('@') -and -not $lastSegment.Contains(':')) {
                ConvertTo-Finding $stage.Line 'DF002' 'error' "Image '$image' has no tag and resolves to latest."
            }
            elseif ($lastSegment -match ':latest$') {
                ConvertTo-Finding $stage.Line 'DF002' 'error' "Image '$image' uses the latest tag."
            }
        }

        $hasRun = @($stage.Instructions | Where-Object Keyword -EQ 'RUN').Count -gt 0
        $pinned = $null -ne $stage.Platform -and $stage.Platform -match 'BUILDPLATFORM'
        $runtimeSide = @(Get-StageChain -Stage $stage -Stages $stages | Where-Object { $_.Index -in $finalChainIndexes }).Count -gt 0
        if (-not $runtimeSide -and $hasRun -and -not $pinned) {
            ConvertTo-Finding $stage.Line 'DF004' 'warning' "Stage '$($stage.Name)' runs commands but is not pinned to --platform=`$BUILDPLATFORM."
        }
    }

    if ($final.Platform) {
        ConvertTo-Finding $final.Line 'DF003' 'error' "The final stage sets --platform=$($final.Platform); leave it unset so buildx resolves the target."
    }

    if ($final.Name -ne 'final') {
        $label = if ($final.Name) { "named '$($final.Name)'" } else { 'unnamed' }
        ConvertTo-Finding $final.Line 'DF023' 'warning' "The last stage is $label; name it 'final'."
    }

    $users = @($finalInstructions | Where-Object Keyword -EQ 'USER')
    if ($users.Count -eq 0) {
        ConvertTo-Finding $final.Line 'DF005' 'error' 'The final stage never sets USER, so it inherits the base image user.'
    }
    elseif ($users[-1].Arguments.Trim() -match '^(root|0)(:.*)?$') {
        ConvertTo-Finding $users[-1].Line 'DF005' 'error' 'The final stage runs as root.'
    }

    foreach ($instruction in @($finalInstructions | Where-Object { $_.Keyword -in @('ENTRYPOINT', 'CMD') })) {
        $arguments = $instruction.Arguments.Trim()
        if (-not $arguments.StartsWith('[')) {
            ConvertTo-Finding $instruction.Line 'DF006' 'error' "$($instruction.Keyword) uses shell form; use exec form so the process receives SIGTERM."
            continue
        }

        $array = @()
        try { $array = @($arguments | ConvertFrom-Json) } catch { $array = @() }
        if ($array.Count -ge 3 -and "$($array[0])" -match '^(/usr)?(/bin/)?(ba|da)?sh$' -and $array[1] -eq '-c' -and "$($array[2])" -notmatch '^\s*exec\s') {
            ConvertTo-Finding $instruction.Line 'DF007' 'error' "$($instruction.Keyword) runs '$($array[0]) -c' without exec, so the shell stays PID 1."
        }
    }

    foreach ($stage in $stages) {
        foreach ($instruction in @($stage.Instructions | Where-Object Keyword -EQ 'RUN')) {
            $text = (@($instruction.Arguments) + $instruction.Heredocs) -join "`n"
            $flat = $text -replace '\\[ \t]*\r?\n', ' '
            $installs = $flat -match '\bapt(-get)?\s+(-\S+\s+)*install\b'
            if ($installs -and $flat -notmatch '--no-install-recommends') {
                ConvertTo-Finding $instruction.Line 'DF008' 'error' 'apt install without --no-install-recommends.'
            }
            if ($installs -and $flat -notmatch 'rm\s+-rf\s+/var/lib/apt/lists' -and $instruction.Arguments -notmatch '--mount=\S*target=/var/lib/apt\b') {
                ConvertTo-Finding $instruction.Line 'DF009' 'error' 'apt install without removing /var/lib/apt/lists in the same RUN.'
            }
            if ($flat -match '\bapt(-get)?\s+(-\S+\s+)*(dist-)?upgrade\b|\bapk\s+upgrade\b') {
                ConvertTo-Finding $instruction.Line 'DF010' 'error' 'Distribution-wide package upgrade; rebuild on a refreshed base image instead.'
            }
            foreach ($heredoc in $instruction.Heredocs) {
                $firstLine = @($heredoc -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 1)
                if ($firstLine.Count -gt 0 -and -not $firstLine[0].StartsWith('#!') -and $firstLine[0] -notmatch '^set\s+-[a-z]*e') {
                    ConvertTo-Finding $instruction.Line 'DF011' 'error' 'Heredoc does not open with `set -eux`, so earlier failures are ignored.'
                }
            }
            if ($flat -match 'case\s+"?\$\{?TARGET(ARCH|PLATFORM|VARIANT)' -and $flat -notmatch '(^|\s)\*\s*\)') {
                ConvertTo-Finding $instruction.Line 'DF012' 'error' 'Platform case statement has no failing *) arm.'
            }
            if ($flat -match '\bif\s+\[\s*"?\$\{?TARGET(ARCH|PLATFORM|VARIANT)' -and $flat -notmatch '\belse\b') {
                ConvertTo-Finding $instruction.Line 'DF012' 'error' 'Platform if-chain has no failing else branch.'
            }
            if ($flat -match '\b(curl|wget)\b[^|;&\n]*\|\s*(sudo\s+)?(ba|da|z)?sh\b') {
                ConvertTo-Finding $instruction.Line 'DF017' 'error' 'Download piped into a shell; fetch a versioned artifact and verify it.'
            }
            if ($stage.Index -in $finalChainIndexes -and $installs -and $flat -match '\binstall\b[^\n]*(\s\S+-dev\b|\sbuild-essential\b)') {
                ConvertTo-Finding $instruction.Line 'DF021' 'warning' 'The runtime stage installs a -dev or meta-package; install only the runtime library.'
            }
        }
    }

    $finalArgs = @(foreach ($instruction in @($finalInstructions | Where-Object Keyword -EQ 'ARG')) {
            foreach ($pair in @(ConvertFrom-KeyValueArgument -Arguments $instruction.Arguments)) {
                [pscustomobject]@{ Name = $pair.Name; Value = $pair.Value; Line = $instruction.Line }
            }
        })
    foreach ($arg in @($finalArgs | Where-Object { $_.Name -in $script:ProvenanceArgs -and $null -eq $_.Value })) {
        ConvertTo-Finding $arg.Line 'DF013' 'error' "Provenance ARG $($arg.Name) has no default; use n/a or 0."
    }
    $argNames = @($finalArgs | ForEach-Object { $_.Name })
    $missingProvenance = @($script:ProvenanceArgs | Where-Object { $_ -notin $argNames })
    if ($missingProvenance.Count -gt 0) {
        ConvertTo-Finding $final.Line 'DF014' 'error' "The final stage is missing provenance ARGs: $($missingProvenance -join ', ')."
    }

    $labelText = @($finalInstructions | Where-Object Keyword -EQ 'LABEL' | ForEach-Object { $_.Arguments }) -join ' '
    $presentKeys = @([regex]::Matches($labelText, 'org\.opencontainers\.image\.([a-z.]+)\s*=') | ForEach-Object { $_.Groups[1].Value })
    $missingKeys = @($script:OciLabelKeys | Where-Object { $_ -notin $presentKeys })
    if ($missingKeys.Count -gt 0) {
        ConvertTo-Finding $final.Line 'DF015' 'error' "The final stage is missing OCI labels: $($missingKeys -join ', ')."
    }

    if ($Shape -ne 'service') {
        foreach ($instruction in @($finalInstructions | Where-Object Keyword -EQ 'EXPOSE')) {
            ConvertTo-Finding $instruction.Line 'DF024' 'warning' "A $Shape image listens on no port; remove EXPOSE or declare the image a service."
        }
    }

    foreach ($instruction in @($Model.Instructions | Where-Object Keyword -EQ 'HEALTHCHECK')) {
        if ($instruction.Arguments.Trim() -notmatch '^NONE$') {
            ConvertTo-Finding $instruction.Line 'DF016' 'error' 'HEALTHCHECK is ignored by Kubernetes; declare health checks in Compose instead.'
        }
    }

    foreach ($comment in @($Model.Comments)) {
        if ($comment.Text -cmatch "^#\s*($script:Keywords)\s+\S") {
            ConvertTo-Finding $comment.Line 'DF018' 'warning' 'Commented-out instruction; delete it or move the tooling into a debug target.'
        }
    }

    foreach ($instruction in @($Model.Instructions | Where-Object { $_.Keyword -in @('ARG', 'ENV') })) {
        foreach ($pair in @(ConvertFrom-KeyValueArgument -Arguments $instruction.Arguments)) {
            if ($pair.Name -match '(?i)(PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|PRIVATE_?KEY|CONNECTION_?STRING)' -and -not [string]::IsNullOrEmpty($pair.Value)) {
                ConvertTo-Finding $instruction.Line 'DF022' 'error' "$($instruction.Keyword) $($pair.Name) bakes a secret-like value into the image."
            }
        }
    }
}

function Get-DockerfileFinding {
    <#
    .SYNOPSIS
        Audits one Dockerfile and returns its profile-filtered findings.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $false)][string]$ImageProfile = 'auto',
        [Parameter(Mandatory = $false)][string]$ContextPath,
        [Parameter(Mandatory = $false)][string[]]$Skip = @()
    )

    $model = Read-DockerfileModel -Line @(Get-Content -LiteralPath $FilePath)
    $resolvedProfile = Resolve-ImageProfile -FilePath $FilePath -Model $model -Requested $ImageProfile
    $shape = Resolve-WorkloadShape -Model $model
    $raw = @(Get-RawFinding -Model $model -Shape $shape) + @(Test-DockerIgnore -FilePath $FilePath -ContextPath $ContextPath)

    $raw |
        Where-Object { $_.Rule -notin $Skip -and (Test-RuleEnabled -Rule $_.Rule -ImageProfile $resolvedProfile) } |
        Sort-Object Line, Rule |
        ForEach-Object {
            [pscustomobject]@{
                Path     = $FilePath
                Profile  = $resolvedProfile
                Shape    = $shape
                Line     = $_.Line
                Rule     = $_.Rule
                Severity = $_.Severity
                Message  = $_.Message
            }
        }
}

function Find-Dockerfile {
    <#
    .SYNOPSIS
        Expands files and directories into Dockerfile paths.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string[]]$Path)

    $results = [Collections.Generic.List[string]]::new()
    foreach ($item in $Path) {
        $full = [IO.Path]::GetFullPath($item)
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $results.Add($full)
            continue
        }
        if (-not (Test-Path -LiteralPath $full -PathType Container)) {
            throw "Path '$item' does not exist. Pass a Dockerfile or a directory."
        }

        $stack = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
        $stack.Push([IO.DirectoryInfo]::new($full))
        while ($stack.Count -gt 0) {
            $directory = $stack.Pop()
            foreach ($file in $directory.EnumerateFiles()) {
                $name = $file.Name
                if ($name -notlike '*.dockerignore' -and ($name -eq 'Dockerfile' -or $name -like 'Dockerfile.*' -or $name -like '*.dockerfile')) {
                    $results.Add($file.FullName)
                }
            }
            foreach ($child in $directory.EnumerateDirectories()) {
                if ($child.Name -notin $script:ExcludedDirectories -and -not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    $stack.Push($child)
                }
            }
        }
    }

    $results | Sort-Object -Unique
}

#endregion

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $files = @(Find-Dockerfile -Path $Path)
        if ($files.Count -eq 0) {
            Write-Warning 'No Dockerfiles found.'
            exit 0
        }

        $findings = @(foreach ($file in $files) {
                Get-DockerfileFinding -FilePath $file -ImageProfile $ImageProfile -ContextPath $ContextPath -Skip $Skip
            })
        $findings

        $errors = @($findings | Where-Object Severity -EQ 'error').Count
        $warnings = @($findings | Where-Object Severity -EQ 'warning').Count
        Write-Host "Audited $($files.Count) Dockerfile(s): $errors error(s), $warnings warning(s)."

        $blocking = switch ($FailOn) {
            'error' { $errors }
            'warning' { $errors + $warnings }
            default { 0 }
        }
        exit $(if ($blocking -gt 0) { 2 } else { 0 })
    }
    catch {
        Write-Error -ErrorAction Continue "Dockerfile audit failed: $($_.Exception.Message)"
        exit 1
    }
}
