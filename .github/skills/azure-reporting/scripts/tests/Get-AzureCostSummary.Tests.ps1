#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Get-AzureCostSummary.ps1') -Subscription 'Example Subscription'
    Mock Start-Sleep {}

    function New-CostResponse {
        param([object[]]$Rows, [string]$NextLink)
        $properties = [ordered]@{
            columns = @(@{ name = 'Cost'; type = 'Number' }, @{ name = 'UsageQuantity'; type = 'Number' }, @{ name = 'ServiceName'; type = 'String' }, @{ name = 'Currency'; type = 'String' })
            rows    = $Rows
        }
        if ($NextLink) { $properties.nextLink = $NextLink }
        return @{ properties = $properties } | ConvertTo-Json -Depth 10
    }
}

Describe 'New-CostQueryBody' {
    It 'builds a custom-period query grouped by the requested dimensions' {
        $body = New-CostQueryBody -From '2026-01-01' -To '2026-01-31' -GroupBy 'ServiceName', 'Meter' | ConvertFrom-Json

        $body.type | Should -Be 'ActualCost'
        $body.timeframe | Should -Be 'Custom'
        $body.timePeriod.from | Should -Be '2026-01-01'
        $body.timePeriod.to | Should -Be '2026-01-31'
        $body.dataset.granularity | Should -Be 'None'
        $body.dataset.grouping.name | Should -Be @('ServiceName', 'Meter')
        $body.dataset.PSObject.Properties.Name | Should -Not -Contain 'filter'
    }

    It 'filters by service name when requested' {
        $body = New-CostQueryBody -From '2026-01-01' -To '2026-01-31' -GroupBy 'Meter' -ServiceName 'Storage' | ConvertFrom-Json

        $body.dataset.filter.dimensions.name | Should -Be 'ServiceName'
        @($body.dataset.filter.dimensions.values) | Should -Be @('Storage')
    }

    It 'rejects a period that ends before it starts' {
        { New-CostQueryBody -From '2026-02-01' -To '2026-01-01' -GroupBy 'ServiceName' } | Should -Throw '*before it starts*'
    }
}

Describe 'ConvertFrom-CostQueryResponse' {
    It 'maps each row onto the column names' {
        $rows = @(ConvertFrom-CostQueryResponse -Response (New-CostResponse -Rows @(, @(1.25, 10, 'Storage', 'EUR')) | ConvertFrom-Json))

        $rows.Count | Should -Be 1
        $rows[0].Cost | Should -Be 1.25
        $rows[0].ServiceName | Should -Be 'Storage'
        $rows[0].Currency | Should -Be 'EUR'
    }
}

Describe 'Invoke-CostQuery' {
    BeforeEach {
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'account' } { "00000000-0000-0000-0000-000000000000`n" }
    }

    It 'posts the body from a temporary file and follows next links' {
        $script:bodies = [Collections.Generic.List[string]]::new()
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'rest' } {
            $script:bodies.Add((Get-Content -LiteralPath ($args[6].TrimStart('@')) -Raw))
            if (($args -join ' ') -like '*page2*') { New-CostResponse -Rows @(, @(2, 1, 'Storage', 'EUR')) }
            else { New-CostResponse -Rows @(, @(1, 1, 'Foundry Models', 'EUR')) -NextLink 'https://management.example.com/page2' }
        }

        $rows = @(Invoke-CostQuery -Subscription 'Example' -Body '{"type":"ActualCost"}' -InitialDelaySeconds 0)

        $rows.ServiceName | Should -Be @('Foundry Models', 'Storage')
        $script:bodies | Should -Be @('{"type":"ActualCost"}', '{"type":"ActualCost"}')
        Should -Invoke Invoke-AzCli -Times 1 -Exactly -ParameterFilter {
            $args[0] -eq 'rest' -and $args[4] -eq 'https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.CostManagement/query?api-version=2023-11-01'
        }
    }

    It 'retries throttled requests and removes the body file' {
        $script:attempt = 0
        $script:bodyFile = $null
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'rest' } {
            $script:bodyFile = $args[6].TrimStart('@')
            $script:attempt++
            if ($script:attempt -lt 3) { throw 'az rest failed: ERROR: Too Many Requests({"error":{"code":"429"}})' }
            New-CostResponse -Rows @()
        }

        @(Invoke-CostQuery -Subscription 'Example' -Body '{}' -InitialDelaySeconds 1).Count | Should -Be 0
        Should -Invoke Start-Sleep -Times 2 -Exactly
        Test-Path -LiteralPath $script:bodyFile | Should -BeFalse
    }

    It 'surfaces other failures without retrying' {
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'rest' } { throw 'az rest failed: ERROR: (AuthorizationFailed)' }

        { Invoke-CostQuery -Subscription 'Example' -Body '{}' } | Should -Throw '*AuthorizationFailed*'
        Should -Invoke Invoke-AzCli -Times 1 -Exactly -ParameterFilter { $args[0] -eq 'rest' }
    }
}
