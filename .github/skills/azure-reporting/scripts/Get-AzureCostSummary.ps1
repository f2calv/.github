#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Summarizes billed Azure costs for a subscription from the Cost Management query API.
.DESCRIPTION
    Posts a Cost Management query grouped by the requested dimensions, follows result pages,
    retries throttled requests and emits one object per result row with the API's column names.
    Costs are in the billing currency and include negotiated rates and credits, unlike retail prices.
.PARAMETER Subscription
    Subscription name or ID, as accepted by the Azure CLI.
.PARAMETER From
    First day of the period. Defaults to the first day of the current month.
.PARAMETER To
    Last day of the period, inclusive. Defaults to today.
.PARAMETER GroupBy
    Cost Management dimensions to group by, for example ServiceName, MeterCategory, Meter,
    ResourceGroupName or ResourceType. At most two.
.PARAMETER ServiceName
    Limits the query to these ServiceName values; discover them by grouping by ServiceName first.
.PARAMETER CostType
    ActualCost (as billed) or AmortizedCost (reservations spread over their term).
.PARAMETER Granularity
    None for one total per group, or Daily for one row per day.
.PARAMETER MaxAttempts
    Attempts per page when the API answers 429 Too Many Requests.
.EXAMPLE
    ./Get-AzureCostSummary.ps1 -Subscription 'Example Subscription'
.EXAMPLE
    ./Get-AzureCostSummary.ps1 -Subscription 'Example Subscription' -GroupBy ServiceName, Meter -ServiceName 'Foundry Models'
.NOTES
    Requires an authenticated Azure CLI and Cost Management Reader (or Reader) on the subscription.
    Cost data typically lags usage by 8 to 24 hours, and the API throttles aggressively per scope.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Subscription,
    [datetime]$From = (Get-Date -Day 1).Date,
    [datetime]$To = (Get-Date).Date,
    [ValidateCount(1, 2)][string[]]$GroupBy = @('ServiceName'),
    [string[]]$ServiceName = @(),
    [ValidateSet('ActualCost', 'AmortizedCost')][string]$CostType = 'ActualCost',
    [ValidateSet('None', 'Daily')][string]$Granularity = 'None',
    [ValidateRange(1, 10)][int]$MaxAttempts = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

. (Join-Path $PSScriptRoot 'AzureReporting.Common.ps1')

#region Pure functions
function New-CostQueryBody {
    [CmdletBinding()][OutputType([string])]
    param(
        [Parameter(Mandatory)][datetime]$From,
        [Parameter(Mandatory)][datetime]$To,
        [Parameter(Mandatory)][string[]]$GroupBy,
        [string[]]$ServiceName = @(),
        [string]$CostType = 'ActualCost',
        [string]$Granularity = 'None'
    )
    if ($To -lt $From) { throw "The period ends ($($To.ToString('yyyy-MM-dd'))) before it starts ($($From.ToString('yyyy-MM-dd')))." }
    $dataset = [ordered]@{
        granularity = $Granularity
        aggregation = [ordered]@{
            totalCost = @{ name = 'Cost'; function = 'Sum' }
            quantity  = @{ name = 'UsageQuantity'; function = 'Sum' }
        }
        grouping    = @($GroupBy | ForEach-Object { @{ type = 'Dimension'; name = $_ } })
    }
    if ($ServiceName.Count -gt 0) {
        $dataset.filter = @{ dimensions = @{ name = 'ServiceName'; operator = 'In'; values = @($ServiceName) } }
    }
    $body = [ordered]@{
        type       = $CostType
        timeframe  = 'Custom'
        timePeriod = [ordered]@{ from = $From.ToString('yyyy-MM-dd'); to = $To.ToString('yyyy-MM-dd') }
        dataset    = $dataset
    }
    return $body | ConvertTo-Json -Depth 10 -Compress
}

function ConvertFrom-CostQueryResponse {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Response)
    $columns = @($Response.properties.columns | ForEach-Object { $_.name })
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($row in @($Response.properties.rows)) {
        $values = @($row)
        $record = [ordered]@{}
        for ($index = 0; $index -lt $columns.Count; $index++) { $record[$columns[$index]] = $values[$index] }
        $rows.Add([pscustomobject]$record)
    }
    return $rows.ToArray()
}
#endregion

function Invoke-CostQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subscription,
        [Parameter(Mandatory)][string]$Body,
        [int]$MaxAttempts = 5,
        [int]$InitialDelaySeconds = 30
    )
    $subscriptionId = (Invoke-AzCli account show --subscription $Subscription --query id --output tsv).Trim()
    # A body file avoids cmd.exe quoting of JSON when az is the Windows .cmd wrapper.
    $bodyFile = New-TemporaryFile
    try {
        Set-Content -LiteralPath $bodyFile -Value $Body -NoNewline
        $uri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
        while ($uri) {
            $pageUri = $uri
            $json = Invoke-WithThrottleRetry -MaxAttempts $MaxAttempts -InitialDelaySeconds $InitialDelaySeconds -Operation {
                Invoke-AzCli rest --method post --url $pageUri --body "@$bodyFile" --output json
            }
            $response = $json | ConvertFrom-Json
            ConvertFrom-CostQueryResponse -Response $response
            $uri = if ($response.properties.PSObject.Properties.Name -contains 'nextLink') { $response.properties.nextLink } else { $null }
        }
    }
    finally {
        Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $body = New-CostQueryBody -From $From -To $To -GroupBy $GroupBy -ServiceName $ServiceName -CostType $CostType -Granularity $Granularity
        Invoke-CostQuery -Subscription $Subscription -Body $body -MaxAttempts $MaxAttempts
    }
    catch {
        Write-Error "Cost query failed: $_" -ErrorAction Continue
        exit 1
    }
}
