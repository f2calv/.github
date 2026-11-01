# Shared Caching Contract

Wire leadership election through the shared caching registration, Redlock configuration and runner.

The established shared integration uses:

| Surface | Role |
| --- | --- |
| `AddCasCapCaching(...)` | Registers caching and, when configured, the distributed-lock factory. |
| `IDistributedLockFactory` | Acquires a resource lease through `CreateLockAsync(...)`. |
| `ILeadershipRunner` | Provisional .NET 8+ checkout API; owns acquisition, loss cancellation, awaited cleanup and reacquisition. |
| `IRedLock` | Exposes ownership state and asynchronous disposal. |
| `IOptions<RedlockConfig>` | Supplies lock configuration and named timing profiles. |
| `RedlockConfig.GetTimings(profileName)` | Resolves timings for the selected use case. |
| `RedlockProfiles.LeaderElection` | Selects leadership timings rather than short cache-miss timings. |
| `RedlockProfiles.CacheMiss` | Selects cache-miss protection, not a singleton-worker lifecycle. |

`RedlockConfig` is in `CasCap.Common.Models`. `GetTimings(...)` returns
`(TimeSpan expiry, TimeSpan wait, TimeSpan retry)`. The inspected shared configuration has these
defaults; verify the consumer's pinned version and overrides before relying on them:

| Timing source | Expiry | Acquisition wait | Retry interval |
| --- | --- | --- | --- |
| Root timings / missing named profile | 5 seconds | 5 seconds | 250 milliseconds |
| Built-in `LeaderElection` profile | 30 seconds | 60 seconds | 5 seconds |

Profiles are stored in `Dictionary<string, RedlockTimingProfile>`. An absent profile falls back to
root timings rather than failing; check that the intended election profile actually resolves.
`RedlockConfig` binds beneath the selected caching section's `Redlock` child, and
`CachingConfig.DistributedLockingEnabled` controls registration. Do not assume the root section
name when the caller overrides it.

## Configuration Ownership for New Abstractions

- Keep `CachingConfig.Redlock` as the single configuration source for both short-lived cache locks
  and leadership leases. A leadership runner consumes the existing `IOptions<RedlockConfig>` and
  registered `IDistributedLockFactory`; do not create a second Redis connection, factory, binding
  section or independently configured copy of expiry, wait, retry, database or key format.
- Preserve the existing distinction: `DistributedCacheService` currently calls `GetTimings()`
  for root cache-miss timings, while election uses `GetTimings(RedlockProfiles.LeaderElection)`.
  Do not move or rename the root configuration, make every lock use election timings, or route
  one-shot cache locking through a perpetual election/reacquisition loop.
- Add genuinely new lifecycle settings, such as loss-observation interval or cleanup budget, only
  where needed under the existing Redlock configuration, scoped to leadership behavior. Keep these
  separate from the Redis lease expiry and acquisition retry settings; do not duplicate equivalent
  knobs in application options or an unrelated feature-host configuration.
- Resolve the same configured Redlock options consistently through every `AddCasCapCaching`
  overload. Validate binding, default/profile selection and factory key/database configuration,
  and add regression coverage showing that changing leadership settings does not change
  cache-miss timings or behavior.
- Build the service provider with `ValidateOnBuild` enabled for local-only caching and disabled
  locking, without an elected worker. Optional runner registration must not make ordinary caching
  require a lock factory; an elected consumer must still fail explicitly when prerequisites are absent.

## Integration Procedure

The [owned-worker example](../examples/owned-worker.md) shows the application callback, registration,
required resource configuration and lifecycle expectations using the existing shared runner.
It deliberately does not implement another acquisition loop or claim package availability.

The current checkout's runner accepts
`RunAsync(string resource, Func<CancellationToken, Task> runAsync, CancellationToken cancellationToken)`.
It uses the existing factory and options, observes `IsAcquired` every
`Redlock.LeadershipCheckIntervalMs` (default `1000`), and backs off by the election retry interval
after contention. Business faults and unexpected normal completion propagate. Cleanup is awaited
without a runner timeout; the consuming host owns forced termination. The feature launcher must
await children, and request host shutdown immediately on a child fault before joining siblings, so
the host shutdown budget still applies when cleanup stalls.

Treat this API as provisional until the remaining use cases prove the contract. Use the existing
Debug project-reference/container dependency mirror and authorized deployment shim rather than
publishing a package for each iteration. For every contract refinement, impact-check all previously
migrated consumers and backfill their wiring, tests and documentation in the same change. Keep
published-package availability distinct from checkout behavior; do not silently claim Release
support against an older package that lacks the runner.

1. Inspect the pinned `CasCap.Common.Caching` and RedLock.net versions and the actual overloads
   before writing calls. A local checkout may contain APIs not yet available in a published package.
   Do not add an independent RedLock factory or direct package reference just to duplicate the
   existing caching integration.
2. Verify the Redis connection and distributed-lock enablement. The shared registration requires
   remote Redis and enabled distributed locking; local-only caching is not cross-process election.
   Fail explicitly for an elected worker with missing prerequisites instead of silently running it
   without a lease.
3. Trace the configured Redis database and `RedisKeyFormat` through factory registration to the
   effective Redis key. Distinguish the logical resource passed to `CreateLockAsync` from the
   formatted storage key; avoid applying the prefix twice.
4. Resolve a dedicated election profile. Treat expiry, acquisition wait, retry interval and any
   outer-loop backoff as separate controls:
   - Expiry is the lease duration supplied to RedLock.net, not a fixed worker execution timeout.
   - Wait bounds an acquisition call; retry spaces attempts inside that call.
   - An outer contention loop can continue after the call fails to acquire.
   - RedLock.net manages renewal; verify the installed version's renewal and loss behavior.
     An application heartbeat does not renew a Redis lease.
5. Choose timings against expected pauses, Redis latency, startup, shutdown and takeover needs.
   Validate supported ranges and combinations. Do not promise takeover in exactly one expiry
   period or reuse short cache-miss timings for an indefinitely running worker.
6. Use deterministic, collision-free resource identities. All replicas of one partition must
   contend on the same effective key; safe independent partitions must use different keys.
   Isolate environments/installations where Redis is shared. Never add a pod ID or run ID to
   the election resource, and do not expose account identifiers through logs or metric labels.
7. Treat changes to database, prefix, resource dimensions or key format as an ownership migration:
   old and new replicas using different keys can both lead. Plan a controlled cutover rather than
   assuming a rolling configuration change preserves mutual exclusion.
