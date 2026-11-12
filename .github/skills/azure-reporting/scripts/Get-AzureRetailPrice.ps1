#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Lists Azure retail (pay-as-you-go list) prices from the public Azure Retail Prices API.
.DESCRIPTION
    Builds an OData filter from the supplied region, service, product and meter-name fragments,
    follows every result page, retries throttled requests and emits one object per meter. Token
    meters priced per 1K or 1M units also carry a normalized PricePerMillion.

    The API needs no authentication and returns list prices only; negotiated, reserved or
    credit-backed rates appear only in Cost Management.
.PARAMETER CurrencyCode
    ISO currency code for the prices, for example USD or EUR.
.PARAMETER Region
    Azure ARM region name, for example swedencentral. Omit to include every region.
.PARAMETER ServiceName
    Exact service name, for example 'Foundry Models' or 'Storage'.
.PARAMETER ProductNameContains
    Case-sensitive fragment that the product name must contain.
.PARAMETER MeterNameContains
    Case-sensitive fragments; a meter matches when its name contains any of them.
.PARAMETER IncludeNonConsumption
    Includes reservation and savings-plan prices as well as pay-as-you-go consumption prices.
.PARAMETER MaxAttempts
    Attempts per page when the API answers 429 Too Many Requests.
.EXAMPLE
    ./Get-AzureRetailPrice.ps1 -CurrencyCode EUR -Region swedencentral -MeterNameContains 'gpt rt aud 0828'
.EXAMPLE
    ./Get-AzureRetailPrice.ps1 -Region westeurope -ServiceName 'Storage' -ProductNameContains 'Blob'
.NOTES
    Converted currencies are rounded to four decimals, which loses precision on small per-1K meters;
    prefer a per-1M meter or the USD price when the fourth decimal matters.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Z]{3}$')][string]$CurrencyCode = 'USD',
    [string]$Region,
    [string]$ServiceName,
    [string]$ProductNameContains,
    [string[]]$MeterNameContains = @(),
    [switch]$IncludeNonConsumption,
    [ValidateRange(1, 10)][int]$MaxAttempts = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

. (Join-Path $PSScriptRoot 'AzureReporting.Common.ps1')

#region Pure functions
function ConvertTo-ODataLiteral {
    [CmdletBinding()][OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function New-RetailPriceFilter {
    [CmdletBinding()][OutputType([string])]
    param(
        [string]$Region,
        [string]$ServiceName,
        [string]$ProductNameContains,
        [string[]]$MeterNameContains = @(),
        [switch]$IncludeNonConsumption
    )
    $clauses = [Collections.Generic.List[string]]::new()
    if (-not $IncludeNonConsumption) { $clauses.Add("type eq 'Consumption'") }
    if ($Region) { $clauses.Add("armRegionName eq $(ConvertTo-ODataLiteral $Region)") }
    if ($ServiceName) { $clauses.Add("serviceName eq $(ConvertTo-ODataLiteral $ServiceName)") }
    if ($ProductNameContains) { $clauses.Add("contains(productName,$(ConvertTo-ODataLiteral $ProductNameContains))") }
    $meters = @($MeterNameContains | Where-Object { $_ } | ForEach-Object { "contains(meterName,$(ConvertTo-ODataLiteral $_))" })
    if ($meters.Count -eq 1) { $clauses.Add($meters[0]) }
    elseif ($meters.Count -gt 1) { $clauses.Add('(' + ($meters -join ' or ') + ')') }
    if ($clauses.Count -eq 0) { throw 'Supply at least one filter; the unfiltered price list has hundreds of thousands of meters.' }
    return $clauses -join ' and '
}

function ConvertTo-RetailPriceRow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Item)
    $perMillion = switch ($Item.unitOfMeasure) {
        '1K' { [decimal]$Item.retailPrice * 1000 }
        '1M' { [decimal]$Item.retailPrice }
        default { $null }
    }
    return [pscustomobject]@{
        ServiceName     = $Item.serviceName
        ProductName     = $Item.productName
        MeterName       = $Item.meterName
        SkuName         = $Item.skuName
        Region          = $Item.armRegionName
        Type            = $Item.type
        UnitOfMeasure   = $Item.unitOfMeasure
        RetailPrice     = [decimal]$Item.retailPrice
        PricePerMillion = $perMillion
        CurrencyCode    = $Item.currencyCode
    }
}
#endregion

#region Remote calls
function Get-RetailPricePage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)
    return Invoke-RestMethod -Uri $Uri -Method Get
}

function Invoke-RetailPriceQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CurrencyCode,
        [Parameter(Mandatory)][string]$Filter,
        [int]$MaxAttempts = 5
    )
    $uri = "https://prices.azure.com/api/retail/prices?currencyCode='$CurrencyCode'&`$filter=$([uri]::EscapeDataString($Filter))"
    $rows = [Collections.Generic.List[object]]::new()
    while ($uri) {
        $pageUri = $uri
        $page = Invoke-WithThrottleRetry -MaxAttempts $MaxAttempts -Operation { Get-RetailPricePage -Uri $pageUri }
        foreach ($item in @($page.Items)) { $rows.Add((ConvertTo-RetailPriceRow -Item $item)) }
        $uri = $page.NextPageLink
    }
    return @($rows | Sort-Object ServiceName, ProductName, MeterName)
}
#endregion

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $filter = New-RetailPriceFilter -Region $Region -ServiceName $ServiceName -ProductNameContains $ProductNameContains `
            -MeterNameContains $MeterNameContains -IncludeNonConsumption:$IncludeNonConsumption
        Invoke-RetailPriceQuery -CurrencyCode $CurrencyCode -Filter $filter -MaxAttempts $MaxAttempts
    }
    catch {
        Write-Error "Retail price query failed: $_" -ErrorAction Continue
        exit 1
    }
}
