#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Reports Azure OpenAI and Foundry model token usage per deployment from Azure Monitor metrics.
.DESCRIPTION
    Lists the Azure AI (Cognitive Services) accounts in a subscription, then reads the selected
    token metrics split by model deployment for the requested period. Emits one object per account,
    deployment, metric and interval. Metrics are retained for 93 days and need no diagnostic setting.
.PARAMETER Subscription
    Subscription name or ID, as accepted by the Azure CLI.
.PARAMETER AccountName
    Limits the report to one account.
.PARAMETER Start
    Start of the period. Defaults to seven days ago.
.PARAMETER End
    End of the period. Defaults to now.
.PARAMETER Interval
    ISO 8601 aggregation interval, for example PT1H or P1D.
.PARAMETER Metric
    Metric names to read; list the available names with 'az monitor metrics list-definitions'.
.EXAMPLE
    ./Get-AzureModelUsage.ps1 -Subscription 'Example Subscription' -Start (Get-Date).AddDays(-2)
.NOTES
    Requires an authenticated Azure CLI and Monitoring Reader (or Reader) on the accounts.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Subscription,
    [string]$AccountName,
    [datetime]$Start = (Get-Date).ToUniversalTime().AddDays(-7),
    [datetime]$End = (Get-Date).ToUniversalTime(),
    [ValidatePattern('^P(T\d+[MH]|\d+D)$')][string]$Interval = 'P1D',
    [string[]]$Metric = @('InputTokens', 'OutputTokens', 'AudioInputTokens', 'AudioOutputTokens', 'cacheReadInputTokens')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

. (Join-Path $PSScriptRoot 'AzureReporting.Common.ps1')

#region Pure functions
function ConvertFrom-ModelMetricResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][object]$Response
    )
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($metric in @($Response.value)) {
        foreach ($series in @($metric.timeseries)) {
            $deployment = @($series.metadatavalues | Where-Object { $_.name.value -eq 'modeldeploymentname' } |
                ForEach-Object { $_.value }) | Select-Object -First 1
            foreach ($point in @($series.data)) {
                if (-not ($point.PSObject.Properties.Name -contains 'total') -or $null -eq $point.total) { continue }
                $rows.Add([pscustomobject]@{
                        Account    = $Account
                        Deployment = $deployment
                        Metric     = $metric.name.value
                        TimeStamp  = [datetimeoffset]$point.timeStamp
                        Total      = [long]$point.total
                    })
            }
        }
    }
    return $rows.ToArray()
}
#endregion

function Invoke-ModelUsageQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subscription,
        [string]$AccountName,
        [Parameter(Mandatory)][datetime]$Start,
        [Parameter(Mandatory)][datetime]$End,
        [Parameter(Mandatory)][string]$Interval,
        [Parameter(Mandatory)][string[]]$Metric
    )
    if ($End -le $Start) { throw 'The period must end after it starts.' }
    $accounts = @(Invoke-AzCli cognitiveservices account list --subscription $Subscription --output json | ConvertFrom-Json)
    if ($AccountName) { $accounts = @($accounts | Where-Object name -EQ $AccountName) }
    if ($accounts.Count -eq 0) { throw 'No matching Azure AI accounts were found in the subscription.' }
    foreach ($account in $accounts) {
        try {
            $json = Invoke-AzCli monitor metrics list --resource $account.id --metrics @Metric `
                --start-time $Start.ToUniversalTime().ToString('o') --end-time $End.ToUniversalTime().ToString('o') `
                --interval $Interval --aggregation Total --filter "ModelDeploymentName eq '*'" --output json
        }
        catch {
            # Speech, vision and other account kinds publish different metrics; report them without failing the rest.
            if ("$_" -notmatch 'Failed to find metric configuration') { throw }
            Write-Warning "Skipped account $($account.name): it does not publish the requested metrics."
            continue
        }
        ConvertFrom-ModelMetricResponse -Account $account.name -Response ($json | ConvertFrom-Json)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-ModelUsageQuery -Subscription $Subscription -AccountName $AccountName -Start $Start -End $End `
            -Interval $Interval -Metric $Metric
    }
    catch {
        Write-Error "Model usage query failed: $_" -ErrorAction Continue
        exit 1
    }
}
