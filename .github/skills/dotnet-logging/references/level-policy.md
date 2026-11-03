# Level Policy

The event budget that keeps operational logs useful at the default `Information` level. Apply it per
workload; record a deliberate exception beside the logging call.

## Level Contract

| Level | Who acts | Volume rule | Examples |
| --- | --- | --- | --- |
| `Critical` | On-call, immediately | Once, then the process exits or stops serving | Unrecoverable startup dependency, corrupted state |
| `Error` | Someone, soon | Once per failed unit of work or failed request | Unhandled exception, 5xx, message moved to a dead-letter queue, job failed |
| `Warning` | Someone, if it persists | Once per transition into a degraded state | Dependency unavailable with retry, slow request, missing data that should exist, failed health probe |
| `Information` | Nobody; it is the audit trail | Scales with work and state changes, never with elapsed time | Startup summary, configuration activated, leadership acquired or lost, request or batch summary, recovered |
| `Debug` | A developer diagnosing | May scale with items, polls and loops | Per-item progress, successful poll, cache hit or miss, disabled feature, repeated failure |
| `Trace`/`Verbose` | A developer, locally | Unbounded; never enabled in a deployed environment by default | Protocol frames, loop internals, suppressed health and static-file summaries |

A useful test: at `Information`, an idle replica writes nothing after startup except deliberate
periodic summaries, each no more often than every few minutes, and a busy replica writes about one
line per request or unit of work.

## Workload Budgets

| Workload | `Information` | `Debug` |
| --- | --- | --- |
| Web API | Startup summary; one request summary per non-trivial request; configuration and leadership changes; shutdown | Request-level detail inside services, cache results, skipped work |
| Background worker or daemon | Start and stop; state transitions; one summary per batch or cycle that did work; recovery | Each poll, empty cycle, standby or follower loop, per-item progress |
| Message consumer | Consumer started, stopped and rebalanced; periodic throughput summary | Each message handled; acknowledgements |
| Finite job or CLI | Start with its parameters' safe shape; one completion summary with counts and duration; process result | Per-item progress, per-page fetches |
| Interactive console | Little or none on the console while the UI renders; route diagnostics to a file or raise the console sink threshold | As for the underlying workload |

Startup summaries name the version, enabled features or roles and the selected environment, never
configuration values, endpoints or identities.

## Failure Transitions

A dependency that fails every poll must not write one Warning per poll. Track the state and log only
the transitions:

```csharp
public sealed partial class InventoryPollBgService(ILogger<InventoryPollBgService> logger, TimeProvider timeProvider) : BackgroundService
{
    private int _consecutiveFailures;
    private DateTimeOffset _failingSince;

    private void OnPollFailed(Exception exception)
    {
        if (_consecutiveFailures++ == 0)
        {
            _failingSince = timeProvider.GetUtcNow();
            LogPollFailing(logger, nameof(InventoryPollBgService), exception);
        }
        else
            LogPollStillFailing(logger, nameof(InventoryPollBgService), _consecutiveFailures);
    }

    private void OnPollSucceeded()
    {
        if (_consecutiveFailures == 0)
            return;
        var downtime = timeProvider.GetUtcNow() - _failingSince;
        LogPollRecovered(logger, nameof(InventoryPollBgService), _consecutiveFailures, downtime);
        _consecutiveFailures = 0;
    }

    [LoggerMessage(Level = LogLevel.Warning, Message = "{ClassName} inventory poll failing, retrying")]
    private static partial void LogPollFailing(ILogger logger, string className, Exception exception);

    [LoggerMessage(Level = LogLevel.Debug, Message = "{ClassName} inventory poll still failing ConsecutiveFailures={ConsecutiveFailures}")]
    private static partial void LogPollStillFailing(ILogger logger, string className, int consecutiveFailures);

    [LoggerMessage(Level = LogLevel.Information, Message = "{ClassName} inventory poll recovered ConsecutiveFailures={ConsecutiveFailures} Downtime={Downtime}")]
    private static partial void LogPollRecovered(ILogger logger, string className, int consecutiveFailures, TimeSpan downtime);
}
```

`ExecuteAsync`, which calls these handlers around each poll, is omitted. Escalate to `Error` only
when the failure crosses a threshold someone must act on, such as a deadline or a retry budget, and
log that once.

## Summaries Instead of Per-Item Lines

- Batch and cycle work logs one `Information` line with counts and duration (`Processed`,
  `Skipped`, `Failed`, `Elapsed`), and nothing at `Information` when the cycle did no work.
- A long-running finite job may add a progress line at a bounded interval, never per item.
- A high-throughput consumer logs a periodic throughput summary; per-message lines are `Debug`.
- Prefer metrics for rates and latencies. A log line answers "what happened"; a counter answers
  "how often".

## Common Noise and Gaps

| Finding | Correction |
| --- | --- |
| Framework `Request starting`/`Request finished` lines plus an application summary | Keep the `Microsoft.AspNetCore` `Warning` override and one request summary |
| Health probes and static files logged at `Information` | Demote successful ones to `Verbose` |
| Warning on every poll of an unavailable dependency | Failure transitions |
| Exception logged by the service, the controller and the exception handler | Log once at the handling boundary; translate or rethrow without logging |
| "Feature disabled" at `Information` or `Warning` on every start of every replica | `Debug`, unless the feature was expected to be configured |
| Lowering the minimum level produces nothing new | The code emits no event there, or an override still filters it; add the missing event at the right level |
| Quiet log viewer while the console shows events | Delivery: a buffering proxy, collector or viewer; diagnose the transport, not the levels |
| Raw path, query string, claims or payloads in properties | Route template, safe identifiers removed, operator diagnostics only behind an explicit expiring switch |
| A missing optional setting warned on every event that needs it | Warn once per setting, then `Debug` |
| A custom resilience `OnRetry` callback logging `Warning` | The resilience library already logs each retry at `Warning`; keep the callback at `Debug` |
| A periodic heartbeat or summary every few seconds | An interval of minutes, or a summary only when work happened |
| A library logging and rethrowing, then the caller logging again | Libraries throw with context; the application boundary logs once |
| A `static readonly` logger created before logging is configured | Create it lazily, or inject `ILogger<T>`; an early static logger can stay silent for the process lifetime |

Compute values such as a downtime into a local before passing them to a logging call; an
expression argument triggers CA1873 even inside a source-generated method call.
