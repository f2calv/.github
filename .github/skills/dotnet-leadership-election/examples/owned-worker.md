# Worker Owned by the Shared Leadership Runner

Use this integration example only with a verified `CasCap.Common.Caching` checkout or package
that exposes `CasCap.Common.Abstractions.ILeadershipRunner.RunAsync`. The API is provisional;
do not infer published availability from these snippets. Target .NET 8 or later.

The shared runner already owns acquisition, RedLock renewal observation, loss cancellation,
awaited cleanup and reacquisition. **Do not copy that implementation into the application.**
This example supplies only the application's protected worker and its registration.

## Worker

The synthetic worker logs a bounded operational event on each tick; it performs no external side
effects. Replace the tick body with the application's awaited work and pass the ownership token
through all of it. The configured resource has no default so missing identity fails startup.

### `Models/SchedulerConfig.cs`

```csharp
using System.ComponentModel.DataAnnotations;

namespace Example.Models;

public sealed record SchedulerConfig
{
    public const string ConfigurationSectionName = "Scheduler";

    [Required, MinLength(1)]
    public required string Resource { get; init; }
}
```

### `Services/SchedulerBgService.cs`

```csharp
using CasCap.Common.Abstractions;
using Example.Models;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Example.Services;

public sealed partial class SchedulerBgService(
    ILogger<SchedulerBgService> logger,
    IOptions<SchedulerConfig> config,
    TimeProvider timeProvider,
    ILeadershipRunner leadershipRunner
    ) : BackgroundService
{
    protected override Task ExecuteAsync(CancellationToken stoppingToken) =>
        leadershipRunner.RunAsync(config.Value.Resource, RunOwnedAsync, stoppingToken);

    private async Task RunOwnedAsync(CancellationToken ownershipToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(10), timeProvider);
        while (await timer.WaitForNextTickAsync(ownershipToken))
        {
            ownershipToken.ThrowIfCancellationRequested();
            LogTick(logger, nameof(SchedulerBgService));
        }
    }

    [LoggerMessage(LogLevel.Debug, "{ClassName} owned scheduler tick")]
    private static partial void LogTick(ILogger logger, string className);
}
```

Each acquisition invokes `RunOwnedAsync` afresh, so its timer belongs to one ownership run.
Cancellation escapes the worker to the runner; there is no catch that hides a business fault.
Dispose any real session with `await using` inside that callback, await every child and keep
cleanup there rather than in an untracked continuation.

## Registration

After the application's existing `AddCasCapCaching(...)` call:

```csharp
builder.Services.AddOptionsWithValidateOnStart<SchedulerConfig>()
    .BindConfiguration(SchedulerConfig.ConfigurationSectionName)
    .ValidateDataAnnotations();
builder.Services.TryAddSingleton(TimeProvider.System);
builder.Services.AddHostedService<SchedulerBgService>();
```

The composition root needs `Example.Models`, `Example.Services`,
`Microsoft.Extensions.DependencyInjection` and
`Microsoft.Extensions.DependencyInjection.Extensions`. It must already register the shared
`ILeadershipRunner` through caching with remote Redis and distributed locking enabled.
Local-only caching is not sufficient. Missing runner registration must fail startup, never trigger
an unelected fallback. Do not register another Redis factory or a second hosted copy of the worker.

Use the existing host failure policy that stops the host on background-service failure.
Do not set `BackgroundServiceExceptionBehavior.Ignore`. The runner waits for ownership cleanup
without its own timeout; host/container termination policy owns the final shutdown budget.

## Configuration Example

This is a **merge fragment**, not a complete host configuration or a Redis connection:

```json
{
    "Scheduler": {
        "Resource": "example:development:scheduler"
    }
}
```

All replicas of this synthetic installation use the same logical resource. Replace the installation
and environment dimensions deliberately; do not append pod/process/run identifiers. Trace the
existing factory's `RedisKeyFormat` to the effective storage key without applying its prefix twice.
Changing any key dimension is an ownership migration, not an ordinary rolling-update-safe rename.

Keep expiry, wait, retry and observation timing under the existing Redlock configuration. Do not
duplicate them in `SchedulerConfig` or add a second election loop around `RunAsync`.

## Lifecycle and Health

This table describes behavior, not additional public state properties on `ILeadershipRunner`.
The example does not invent a readiness flag or equate the logged tick with lease renewal.

| Event | Runner/worker behavior | Health interpretation |
| --- | --- | --- |
| Contention | Callback does not start; runner waits/retries | Healthy standby is not a liveness failure |
| Acquisition | New callback and timer start | Ownership alone does not establish business readiness |
| Observed lease loss | Runner cancels callback, awaits cleanup, disposes lease, then contends again | Withdraw business readiness before waiting for cleanup |
| Host shutdown | Host token cancels acquisition/current run; protected work stops before lease disposal | Stopping, not a recoverable business error |
| Business exception | Cleanup is awaited and failure escapes the runner | Host failure policy applies; do not silently retry all faults |
| Unexpected callback completion | Runner fails rather than hot-spinning | A perpetual worker ending is not success |

Polling has a detection delay. An already-expired lease cannot exclude a new owner while the old
worker cleans up. This example provides neither downstream fencing nor exactly-once delivery.
Use the skill's state/health and external-connection guidance for workers with readiness,
callbacks or several cooperating loops.

## Validate Without Redis First

With test approval, use a fake `ILeadershipRunner` that captures but does not immediately invoke the
callback. Prove there is no protected work before acquisition; invoke it with a distinct ownership
token; cancel that token while leaving the host token uncancelled; assert the callback finishes
before a second ownership callback begins. Also propagate a synthetic runner failure through the
host's configured failure policy.

Those consumer tests do not test RedLock renewal. Use the shared runner's existing factory/lease
fake tests for acquisition, loss and disposal ordering. Actual multi-replica contention and
renewal require separately approved shared-Redis integration tests. Do not claim those guarantees
from compiling this example or from one logged tick.
