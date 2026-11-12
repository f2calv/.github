#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Get-AzureRetailPrice.ps1')
    Mock Start-Sleep {}
}

Describe 'New-RetailPriceFilter' {
    It 'limits to consumption prices and joins the supplied clauses' {
        New-RetailPriceFilter -Region 'swedencentral' -ServiceName 'Storage' -ProductNameContains 'Blob' |
            Should -Be "type eq 'Consumption' and armRegionName eq 'swedencentral' and serviceName eq 'Storage' and contains(productName,'Blob')"
    }

    It 'ors several meter-name fragments' {
        New-RetailPriceFilter -MeterNameContains 'gpt rt', 'Realtime' -IncludeNonConsumption |
            Should -Be "(contains(meterName,'gpt rt') or contains(meterName,'Realtime'))"
    }

    It 'escapes single quotes in literals' {
        New-RetailPriceFilter -ServiceName "O'Brien" | Should -BeLike "*serviceName eq 'O''Brien'"
    }

    It 'refuses an unfiltered query' {
        { New-RetailPriceFilter -IncludeNonConsumption } | Should -Throw '*at least one filter*'
    }
}

Describe 'ConvertTo-RetailPriceRow' {
    It 'normalizes per-1K token prices to per-million' -ForEach @(
        @{ Unit = '1K'; Price = 0.032; Expected = 32 }
        @{ Unit = '1M'; Price = 28.73; Expected = 28.73 }
        @{ Unit = '1 Hour'; Price = 1.83; Expected = $null }
    ) {
        $item = [pscustomobject]@{
            serviceName = 'Foundry Models'; productName = 'Example'; meterName = 'example meter'; skuName = 'Global'
            armRegionName = 'swedencentral'; type = 'Consumption'; unitOfMeasure = $Unit; retailPrice = $Price; currencyCode = 'USD'
        }
        (ConvertTo-RetailPriceRow -Item $item).PricePerMillion | Should -Be $Expected
    }
}

Describe 'Invoke-RetailPriceQuery' {
    BeforeAll {
        function New-PriceItem([string]$Meter) {
            [pscustomobject]@{
                serviceName = 'Foundry Models'; productName = 'Example'; meterName = $Meter; skuName = 'Global'
                armRegionName = 'swedencentral'; type = 'Consumption'; unitOfMeasure = '1M'; retailPrice = 1.5; currencyCode = 'EUR'
            }
        }
    }

    It 'follows every page and requests the currency with an encoded filter' {
        Mock Get-RetailPricePage -ParameterFilter { $Uri -like '*currencyCode=*' } {
            [pscustomobject]@{ Items = @(New-PriceItem 'b meter'); NextPageLink = 'https://prices.example.com/page2' }
        }
        Mock Get-RetailPricePage -ParameterFilter { $Uri -eq 'https://prices.example.com/page2' } {
            [pscustomobject]@{ Items = @(New-PriceItem 'a meter'); NextPageLink = $null }
        }

        $rows = @(Invoke-RetailPriceQuery -CurrencyCode 'EUR' -Filter "type eq 'Consumption'")

        $rows.MeterName | Should -Be @('a meter', 'b meter')
        Should -Invoke Get-RetailPricePage -Times 1 -Exactly -ParameterFilter {
            $Uri -eq "https://prices.azure.com/api/retail/prices?currencyCode='EUR'&`$filter=type%20eq%20%27Consumption%27"
        }
    }

    It 'retries a throttled page' {
        $script:calls = 0
        Mock Get-RetailPricePage {
            $script:calls++
            if ($script:calls -eq 1) { throw 'Response status code does not indicate success: 429 (Too Many Requests).' }
            [pscustomobject]@{ Items = @(New-PriceItem 'a meter'); NextPageLink = $null }
        }

        @(Invoke-RetailPriceQuery -CurrencyCode 'USD' -Filter 'x').Count | Should -Be 1
        Should -Invoke Start-Sleep -Times 1 -Exactly
    }

    It 'does not retry other failures' {
        Mock Get-RetailPricePage { throw 'Response status code does not indicate success: 400 (Bad Request).' }

        { Invoke-RetailPriceQuery -CurrencyCode 'USD' -Filter 'x' } | Should -Throw '*400*'
        Should -Invoke Get-RetailPricePage -Times 1 -Exactly
    }

    It 'gives up after the maximum attempts' {
        Mock Get-RetailPricePage { throw 'Too Many Requests' }

        { Invoke-RetailPriceQuery -CurrencyCode 'USD' -Filter 'x' -MaxAttempts 3 } | Should -Throw '*Too Many Requests*'
        Should -Invoke Get-RetailPricePage -Times 3 -Exactly
    }
}
