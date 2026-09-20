#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Waits until package versions are available from the NuGet restore endpoint.
.DESCRIPTION
    Polls the NuGet flat-container version index for every supplied package ID.
    Exits successfully only when the exact version is available for all packages.
.PARAMETER PackageId
    One or more NuGet package IDs expected from the release.
.PARAMETER Version
    Exact normalized package version expected from the release.
.PARAMETER TimeoutSeconds
    Maximum total polling duration. Defaults to 600 seconds.
.PARAMETER InitialDelaySeconds
    Delay after the first unsuccessful check. Defaults to 5 seconds.
.PARAMETER MaximumDelaySeconds
    Maximum delay between checks. Defaults to 30 seconds.
.EXAMPLE
    ./Test-NuGetPackageAvailability.ps1 -PackageId Example.Core,Example.Json -Version 1.2.3
.NOTES
    Requires unauthenticated HTTPS access to api.nuget.org.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string[]]$PackageId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[0-9A-Za-z.+-]+$')]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 600,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3600)]
    [int]$InitialDelaySeconds = 5,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3600)]
    [int]$MaximumDelaySeconds = 30
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

function Test-NuGetPackageAvailability {
    <#
    .SYNOPSIS
        Polls NuGet until all requested packages expose an exact version.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$PackageId,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [int]$InitialDelaySeconds,

        [Parameter(Mandatory = $true)]
        [int]$MaximumDelaySeconds
    )

    $BaseUri = [uri]'https://api.nuget.org/v3-flatcontainer/'
    $NormalizedVersion = $Version.ToLowerInvariant()
    $Pending = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Id in $PackageId) {
        $null = $Pending.Add($Id)
    }

    $Stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $DelaySeconds = $InitialDelaySeconds

    while ($Pending.Count -gt 0) {
        foreach ($Id in @($Pending)) {
            $RemainingSeconds = $TimeoutSeconds - [int]$Stopwatch.Elapsed.TotalSeconds
            if ($RemainingSeconds -le 0) {
                break
            }

            $NormalizedId = $Id.ToLowerInvariant()
            $IndexUri = [uri]::new($BaseUri, "$NormalizedId/index.json")
            $RequestTimeoutSeconds = [Math]::Max(1, [Math]::Min(30, $RemainingSeconds))

            try {
                $Response = Invoke-RestMethod `
                    -Uri $IndexUri `
                    -Method Get `
                    -TimeoutSec $RequestTimeoutSeconds
                $Versions = if ($Response.PSObject.Properties.Name -contains 'versions') {
                    @($Response.versions | ForEach-Object { $_.ToString().ToLowerInvariant() })
                }
                else {
                    @()
                }

                if ($NormalizedVersion -in $Versions) {
                    $null = $Pending.Remove($Id)
                    Write-Verbose "$Id $Version is available."
                }
            }
            catch {
                $StatusCode = [int]$_.Exception.Response.StatusCode
                if ($StatusCode -notin @(0, 404, 429)) {
                    throw "NuGet request for $Id failed permanently with HTTP $StatusCode."
                }

                Write-Verbose "$Id $Version is not available yet: $($_.Exception.Message)"
            }
        }

        if ($Pending.Count -eq 0 -or $Stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            break
        }

        $RemainingSeconds = [Math]::Max(1, $TimeoutSeconds - [int]$Stopwatch.Elapsed.TotalSeconds)
        $SleepSeconds = [Math]::Min($DelaySeconds, $RemainingSeconds)
        Write-Verbose "Waiting $SleepSeconds second(s) for $($Pending.Count) package(s)."
        Start-Sleep -Seconds $SleepSeconds
        $DelaySeconds = [Math]::Min($DelaySeconds * 2, $MaximumDelaySeconds)
    }

    $CheckedAtUtc = [DateTimeOffset]::UtcNow
    foreach ($Id in $PackageId) {
        [pscustomobject]@{
            PackageId    = $Id
            Version      = $Version
            SourceUri    = $BaseUri.AbsoluteUri
            Available    = -not $Pending.Contains($Id)
            CheckedAtUtc = $CheckedAtUtc
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $Results = @(Test-NuGetPackageAvailability `
            -PackageId $PackageId `
            -Version $Version `
            -TimeoutSeconds $TimeoutSeconds `
            -InitialDelaySeconds $InitialDelaySeconds `
            -MaximumDelaySeconds $MaximumDelaySeconds)

    $Results
    if (@($Results | Where-Object { -not $_.Available }).Count -gt 0) {
        exit 2
    }

    exit 0
}
