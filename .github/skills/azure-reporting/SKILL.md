---
name: azure-reporting
description: 'Report Azure costs, usage and list prices from the command line: subscription cost by service, resource group or meter (AKS, storage, AI and others), Azure OpenAI and Foundry token usage per deployment from Azure Monitor, retail prices in any currency, and per-call or per-feature cost estimates. Use when asked what something costs or will cost, why a bill changed, or how many tokens a model deployment used.'
compatibility: 'The scripts require PowerShell 7.4 and an authenticated Azure CLI; the retail price script needs neither credentials nor the CLI.'
---

# Azure Reporting

## Overview

Three sources answer different questions. Pick by the question, then combine them:

| Question | Source | Script |
| --- | --- | --- |
| What did we pay, and for what? | Cost Management query API | `Get-AzureCostSummary.ps1` |
| How much did a model deployment process? | Azure Monitor platform metrics | `Get-AzureModelUsage.ps1` |
| What does a unit cost at list price? | Azure Retail Prices API (public) | `Get-AzureRetailPrice.ps1` |

- **Billed cost** is in the billing currency, after negotiated rates and credits, and lags usage by
  8 to 24 hours. A same-day test never shows up there yet.
- **Metrics** arrive within minutes, are kept for 93 days and need no diagnostic setting, but carry
  counts, not money.
- **Retail prices** are list prices only. Multiply metric counts by them for an estimate that is
  current today, then reconcile against billed cost once it lands.

All three are read-only. Script output contains subscription, account and deployment names; treat it
as private and keep it out of public repositories, issues and pull requests.

## Subscription Costs

```powershell
$scripts = './.github/skills/azure-reporting/scripts'
& "$scripts/Get-AzureCostSummary.ps1" -Subscription '<subscription>'                       # month to date by service
& "$scripts/Get-AzureCostSummary.ps1" -Subscription '<subscription>' -GroupBy ResourceGroupName
& "$scripts/Get-AzureCostSummary.ps1" -Subscription '<subscription>' -GroupBy ServiceName, Meter -ServiceName 'Storage'
& "$scripts/Get-AzureCostSummary.ps1" -Subscription '<subscription>' -From 2026-01-01 -To 2026-01-31 -Granularity Daily
```

- Group by `ServiceName` first; its values (for example `Foundry Models`, `Azure Kubernetes Service`,
  `Storage`, `Bandwidth`) are what `-ServiceName` filters accept. Other useful dimensions are
  `MeterCategory`, `MeterSubCategory`, `Meter`, `ResourceGroupName`, `ResourceType` and
  `ResourceLocation`; the API allows two per query.
- Use `-CostType AmortizedCost` when reservations or savings plans should be spread over their term.
- AKS cost appears under the node pool's virtual machines, disks, load balancer and public IPs, often
  in the managed `MC_*` resource group; group by `ResourceGroupName` to attribute it.
- The API throttles hard per scope (429 after a few queries a minute). The script retries with
  backoff from 30 seconds; batch questions into fewer, wider queries rather than many narrow ones.

## Model Token Usage

```powershell
& "$scripts/Get-AzureModelUsage.ps1" -Subscription '<subscription>' -Start (Get-Date).AddDays(-2) -Interval PT1H |
    Where-Object Total | Format-Table Account, Deployment, Metric, TimeStamp, Total
```

- The script lists every Azure AI account in the subscription and splits metrics by
  `ModelDeploymentName`. Speech, Document Intelligence and other kinds publish different metrics and
  are skipped with a warning; read their names with `az monitor metrics list-definitions`.
- Default metrics: `InputTokens` and `OutputTokens` are **text** tokens; `AudioInputTokens` and
  `AudioOutputTokens` are counted separately; together the four match the provider's own
  `response.done` usage total. Text input dominates realtime calls because instructions, tool schemas
  and history are re-sent for every response.
- `cacheReadInputTokens` is often empty for realtime deployments even when the provider reports
  cached input; take cache hits from application-side usage when the estimate depends on them.
- Intervals align to `-Start`. Pass a UTC-midnight start (`[datetime]::UtcNow.Date.AddDays(-7)`) for
  calendar-day buckets, and `PT1H` to line usage up with application logs.
- Metrics cover a deployment, not a user or call. For per-call cost, the application must log or
  persist the provider's usage per call; check how long it keeps that record before relying on it.

## List Prices

```powershell
& "$scripts/Get-AzureRetailPrice.ps1" -CurrencyCode EUR -Region swedencentral -MeterNameContains 'gpt rt aud 0828', 'gpt rt txt 0828'
& "$scripts/Get-AzureRetailPrice.ps1" -Region westeurope -ServiceName 'Storage' -ProductNameContains 'Blob'
```

- Meter names are abbreviated and inconsistent between model generations, for example
  `gpt rt aud 0828 Inp glbl` (`gpt-realtime` 2025-08-28 audio input, Global) beside
  `gpt-realtime-2 Audio inp Gl`. `contains` is case-sensitive; search a short fragment of the model
  version first, then narrow.
- Match the deployment SKU: `glbl`/`Gl` is Global Standard, `DZ`/`DZone` is Data Zone, `regn` is
  regional. Read the SKU with `az cognitiveservices account deployment list`.
- Converted currencies are rounded to four decimals, so a per-1K meter loses precision (EUR
  `0.0287` per 1K becomes 28.70 per million instead of 28.73). Prefer an equivalent per-1M meter from
  the same model family, or the USD price, when the last digits matter. `PricePerMillion` normalizes
  1K and 1M token units.
- The public API also throttles; the script retries with backoff from 10 seconds.

## Estimating A Feature's Cost

1. Read the deployment's model, version, region and SKU.
2. Read token metrics per hour around a known test, and the application's own per-call usage if it
   records one.
3. Price each token class (text/audio, input/cached input/output) with the matching retail meter.
4. Scale by expected duration or volume; state assumptions such as cache hit rate, because
   uncached re-sent context can change the result by an order of magnitude.
5. Reconcile with `Get-AzureCostSummary.ps1 -GroupBy ServiceName, Meter` a day later.

Applications that estimate cost themselves should take prices from configuration, copied from this
API, rather than calling it at runtime.

## Testing

`scripts/Invoke-Tests.ps1` runs the Pester suites with every Azure call mocked. The scripts
themselves are read-only, so running them for a requested report needs no further confirmation.

## Maintaining This Skill

- Cost Management `query` API version, dimension names, page `nextLink` shape and throttling limits.
- Azure Monitor metric names for Azure OpenAI and Foundry (`InputTokens`, `AudioInputTokens`,
  `cacheReadInputTokens`), and whether text and audio counts stay separate.
- Retail Prices API meter-naming scheme for new model generations, currency rounding and the
  `type`/`unitOfMeasure` values the price normalization recognizes.
- Azure CLI argument handling on Windows, where `az` is a `.cmd` wrapper that mangles complex
  `--query` expressions and inline JSON; the scripts filter in PowerShell and post bodies from files.
