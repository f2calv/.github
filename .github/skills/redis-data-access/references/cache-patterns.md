# Cache Patterns

Load this reference before implementing any caching behaviour other than a plain cache-aside read.
`CasCap.Common.Caching` implements cache-aside only. Each other pattern changes who owns loading or
writing and what consistency the caller gets, so it is a design decision, not a per-call option.

## Pattern Selection

| Pattern | Who loads or writes | Consistency | Where it belongs |
| --- | --- | --- | --- |
| Cache-aside | Caller supplies a loader on a miss | Stale until expiry or invalidation | `IDistributedCache.Get<T>(key, createItem, ...)` |
| Read-through | Cache owns a registered loader per key type | Same as cache-aside | A thin typed wrapper over cache-aside, only when many call sites repeat one loader |
| Write-through | Writer updates the authority, then the cache, synchronously | Fresh after the write returns | Application repository or service, never the shared library |
| Write-behind | Writer updates the cache; a background flusher writes the authority later | Authority lags; data can be lost | Avoid unless a durable queue, idempotent flush and single flusher are designed in |
| Refresh-ahead | Background refresh before expiry | Readers rarely see a miss | Not in the library yet; implement per feature only for slow, hot keys |
| Invalidation | Writer deletes or publishes after changing the authority | Bounded by propagation delay | `IDistributedCache.Delete` plus local pub/sub invalidation |

## Cache-Aside

The default. Use it unless a measured problem rules it out.

- Pass a loader that reads the authority and nothing else. Do not write to other keys from inside the
  loader; the per-key lock is held while it runs, so nested calls for the same key deadlock.
- Keep the loader cancellable where the source supports it, even though `Get<T>` does not accept a
  token yet; capture the caller's token in the closure.
- A loader that returns `null` is not cached. Return an explicit empty value with a short absolute
  expiry when "not found" is common and expensive (negative caching).

## Write Ordering

Update the authority first, then delete the cache key:

```text
writer:  UPDATE authority  ->  DEL cache key
reader:  GET miss          ->  load authority  ->  SET cache key
```

- **Delete, do not set.** Setting the cache from the writer races with a reader that loaded the old
  value before the write and stores it after the delete. Deleting forces the next reader to load the
  committed value.
- **Delete after commit.** Deleting before the authority commits lets a reader repopulate the old
  value in the gap.
- A residual race remains: a reader that loaded before the commit can still store the old value after
  the delete. Bound it with a short TTL on volatile keys, or delete again after a short delay when the
  key is hot and correctness matters.
- Write-through (setting the cache after a committed write) is acceptable only when one writer owns
  the key and writes are serialized, so no reader can interleave.

## Write-Behind

Do not add write-behind to the shared library. It makes Redis the temporary authority, so a Redis
failure or eviction loses acknowledged writes. A feature that genuinely needs it must provide:

- a durable queue for pending writes, such as a stream on an endpoint that is never evicted;
- exactly one flusher, coordinated through the `leadership-election` skill;
- idempotent flushes keyed by a business identifier, because retries and failover replay entries;
- explicit monitoring of flush lag and a documented recovery path.

## Refresh-Ahead

Refresh-ahead reloads an entry in the background before it expires, so readers rarely pay the load
cost. It suits a small number of hot keys with slow sources.

- Trigger the refresh when a read finds the entry within a threshold of its expiry, for example the
  last 20% of the TTL. Serve the current value immediately.
- Run the refresh under the same per-key lock so only one instance reloads.
- Never refresh keys nobody reads; let them expire.

The library does not implement this yet. Record any per-feature implementation as a candidate for the
library, and evaluate `Microsoft.Extensions.Caching.Hybrid` or FusionCache before building a general
version, since both already provide layered caching with stampede protection.

## Stampede Protection

A stampede is many callers missing the same key at once and all calling the source.

| Layer | Protection |
| --- | --- |
| One process | The library's per-key async lock runs the loader once; waiters re-read the entry. |
| Several instances | `DistributedLockingEnabled` adds a Redlock per key with the root cache-miss timings. |
| Synchronized expiry | Add jitter to absolute expiries so entries written together expire apart. |
| Hot key | Refresh-ahead, or a longer TTL with explicit invalidation on write. |

Do not enable distributed locking for cheap loaders; the lock round trips can cost more than the
duplicate load. Enable it when the source is slow, rate limited or charged per call.

## Local Cache Layer

Each instance keeps a local copy (memory or disk) in front of Redis.

- `Set` and `Delete` publish the key on a pub/sub channel; other instances drop their local copy when
  `LocalCacheInvalidationEnabled` is on. Pub/sub is fire-and-forget: a disconnected instance misses
  the message and keeps its copy until the local expiry.
- Give the local layer an expiry no longer than the staleness the readers tolerate, because
  invalidation is best effort.
- Read keys that must reflect writes immediately on every instance through `IRemoteCache` directly,
  which has no local layer, rather than through `IDistributedCache`.
