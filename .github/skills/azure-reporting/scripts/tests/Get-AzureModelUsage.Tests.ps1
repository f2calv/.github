#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Get-AzureModelUsage.ps1') -Subscription 'Example Subscription'

    function New-MetricResponse {
        param([string]$Metric, [string]$Deployment, [object[]]$Points)
        [pscustomobject]@{
            value = @([pscustomobject]@{
                    name       = [pscustomobject]@{ value = $Metric }
                    timeseries = @([pscustomobject]@{
                            metadatavalues = @([pscustomobject]@{ name = [pscustomobject]@{ value = 'modeldeploymentname' }; value = $Deployment })
                            data           = $Points
                        })
                })
        }
    }
}

Describe 'ConvertFrom-ModelMetricResponse' {
    It 'emits one row per deployment, metric and interval with a total' {
        $response = New-MetricResponse -Metric 'AudioInputTokens' -Deployment 'example-realtime' -Points @(
            [pscustomobject]@{ timeStamp = '2026-01-01T00:00:00Z'; total = 4054.0 }
            [pscustomobject]@{ timeStamp = '2026-01-02T00:00:00Z'; total = $null }
            [pscustomobject]@{ timeStamp = '2026-01-03T00:00:00Z' }
        )

        $rows = @(ConvertFrom-ModelMetricResponse -Account 'example-account' -Response $response)

        $rows.Count | Should -Be 1
        $rows[0].Account | Should -Be 'example-account'
        $rows[0].Deployment | Should -Be 'example-realtime'
        $rows[0].Metric | Should -Be 'AudioInputTokens'
        $rows[0].Total | Should -Be 4054
        $rows[0].TimeStamp | Should -Be ([datetimeoffset]'2026-01-01T00:00:00Z')
    }

    It 'returns nothing for an empty response' {
        @(ConvertFrom-ModelMetricResponse -Account 'example-account' -Response ([pscustomobject]@{ value = @() })).Count | Should -Be 0
    }
}

Describe 'Invoke-ModelUsageQuery' {
    BeforeAll {
        $script:accounts = '[{"name":"example-a","id":"/subscriptions/00000000-0000-0000-0000-000000000000/a"},{"name":"example-b","id":"/subscriptions/00000000-0000-0000-0000-000000000000/b"}]'
        $script:metrics = New-MetricResponse -Metric 'InputTokens' -Deployment 'example-model' -Points @(
            [pscustomobject]@{ timeStamp = '2026-01-01T00:00:00Z'; total = 10.0 }
        ) | ConvertTo-Json -Depth 10
        $script:period = @{ Start = [datetime]'2026-01-01'; End = [datetime]'2026-01-02'; Interval = 'P1D'; Metric = @('InputTokens') }
    }

    It 'queries metrics split by deployment for the selected account only' {
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'cognitiveservices' } { $script:accounts }
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'monitor' } { $script:metrics }

        $rows = @(Invoke-ModelUsageQuery -Subscription 'Example' -AccountName 'example-b' @script:period)

        $rows.Count | Should -Be 1
        $rows[0].Account | Should -Be 'example-b'
        Should -Invoke Invoke-AzCli -Times 1 -Exactly -ParameterFilter {
            $args[0] -eq 'monitor' -and ($args -join ' ') -like "*--resource /subscriptions/00000000-0000-0000-0000-000000000000/b *--filter ModelDeploymentName eq '``*'*"
        }
    }

    It 'skips accounts that do not publish the requested metrics' {
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'cognitiveservices' } { $script:accounts }
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'monitor' -and ($args -join ' ') -like '*/a *' } {
            throw 'az monitor metrics failed: ERROR: (BadRequest) Failed to find metric configuration for provider'
        }
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'monitor' -and ($args -join ' ') -like '*/b *' } { $script:metrics }

        $rows = @(Invoke-ModelUsageQuery -Subscription 'Example' @script:period -WarningVariable warnings -WarningAction SilentlyContinue)

        $rows.Account | Should -Be @('example-b')
        $warnings | Should -BeLike '*example-a*'
    }

    It 'propagates other metric failures' {
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'cognitiveservices' } { $script:accounts }
        Mock Invoke-AzCli -ParameterFilter { $args[0] -eq 'monitor' } { throw 'az monitor metrics failed: ERROR: (AuthorizationFailed)' }

        { Invoke-ModelUsageQuery -Subscription 'Example' @script:period } | Should -Throw '*AuthorizationFailed*'
    }

    It 'fails clearly when no account matches' {
        Mock Invoke-AzCli { '[]' }

        { Invoke-ModelUsageQuery -Subscription 'Example' @script:period } | Should -Throw '*No matching Azure AI accounts*'
    }

    It 'rejects an empty period' {
        { Invoke-ModelUsageQuery -Subscription 'Example' -Start '2026-01-02' -End '2026-01-01' -Interval 'P1D' -Metric 'InputTokens' } |
            Should -Throw '*must end after it starts*'
    }
}
