---
name: redis-data-access
description: 'Design, implement, audit or troubleshoot Redis data access in .NET services: key roles (cache, state, stream, lock), cache-aside through CasCap.Common.Caching, absolute versus sliding expiration, TTL jitter, invalidation, cache stampedes, hashes, sorted-set series, streams and consumer groups, keyspace notifications, eviction policy and Sentinel endpoint placement. Use when adding a cached read, choosing a Redis data type, setting an expiration, placing keys on an endpoint, or diagnosing stale, missing, evicted or duplicated Redis data.'
argument-hint: 'mode={design|apply|audit|diagnose} [scope=feature|application|workspace]'
user-invocable: true
---

# Redis Data Access

Redis is a fast shared layer in front of an authoritative store, and a home for data whose loss is
acceptable or recoverable: derived snapshots, time series, event streams and coordination leases.
Decide that role for every key before choosing a data type, an expiry or an endpoint.

| Concern | Authority |
| --- | --- |
| Key names, type segments, consumer-group names, stats and lock key formats | [Redis instructions](../../instructions/dotnet.redis.instructions.md) |
| Redlock leader election, lease lifecycle and failover behaviour | [`leadership-election` skill](../leadership-election/SKILL.md) |
| Options types, validation and appsettings layering | [Configuration instructions](../../instructions/dotnet.configuration.instructions.md) |
| Key roles, cache patterns, expiry, invalidation, streams, endpoint placement and validation | This skill |

Do not restate rules from those files here; link to them.

## Modes and Boundaries

| Mode | Outcome |
| --- | --- |
| `design` | Classify the data, choose the type, expiry, invalidation and endpoint, and record the decision. No edits. |
| `apply` | Implement the agreed design, wire configuration, update documentation and add deterministic tests. |
| `audit` | Inventory Redis access and uncached repeated reads, and report role, expiry, invalidation and placement gaps without edits. |
| `diagnose` | Trace one symptom (stale, missing, evicted or duplicated data) to its cause. |

- Never write, delete, flush, expire or rename live Redis keys, create or destroy consumer groups, or
  change server configuration without explicit authorization. Diagnose with read-only commands.
- Ask before running tests, including Redis-backed integration tests.
- Keep real hostnames, addresses, database numbers and private key layouts out of public files. Use
  synthetic domains such as `catalog` or `orders` in examples.
- In an audit, confirm every finding against the code before reporting it. Pattern searches
  routinely misreport immutable versioned keys as stale, miss a TTL set on a separate line, and
  treat consumer names built from the pod hostname as shared across replicas.

## 1. Classify Every Key by Role

| Role | Type segment | Authority | Expiry | Loss impact | Endpoint need |
| --- | --- | --- | --- | --- | --- |
| Cache | `cache` | Another store or API | Always | Refill cost only | May be evicted |
| State | `snapshot`, `series`, `stats` | Redis, rebuildable or loss-tolerant | Partitioned keys only | Gap until rebuilt | Must not be evicted |
| Stream | `stream` | Redis as transport | Trim, never `EXPIRE` | Lost or replayed events | Must not be evicted |
| Lock | `lock` | Redis lease | Lease TTL | Two owners if lost | Must never fail over |

1. Inventory every key the change touches: its format string, type, writer, readers, expiry and
   configured database. Search `appsettings*.json`, Lua scripts and code; keys are often composed.
2. Assign exactly one role per key. Split a key that mixes roles, such as a hash holding both cached
   copies and authoritative state.
3. Keep Redis the system of record only when losing the data is acceptable or it can be rebuilt from
   a source. Otherwise the database or upstream API stays authoritative and Redis is a cache.
4. Record the role beside the key's configuration or in the application README so a reader can tell
   whether deleting it is safe.

## 2. Choose the Data Type

| Access pattern | Type | Notes |
| --- | --- | --- |
| One serialized object by identifier | String | The shared cache stores JSON or MessagePack strings. |
| Current value per entity | Hash | One field per entity under a `snapshot` key; read with `HGET` or `HMGET`. |
| Readings over time | Sorted set | Score is UTC ticks; partition keys by date and range-query by score. |
| Ordered events with consumers | Stream | Consumer groups give at-least-once delivery with acknowledgements. |
| Membership or de-duplication | Set | Bound the size or give partitioned keys a TTL. |

- Bound every collection: partition by date or entity and expire partitions, or trim streams.
  Unbounded hashes, sets and streams become large keys that block the server when read or deleted.
- Never use `KEYS` in application code. StackExchange.Redis `IServer.Keys`/`KeysAsync` pages with
  `SCAN`, so it does not block the server, but it still walks every key in the database, including
  other applications' keys on a shared database. To list entities, add each key to an index set on
  write and read the set, then fetch the members in one batch.
- Fetch only what the caller needs (`HMGET`, `ZRANGE ... BYSCORE LIMIT`, `XREADGROUP COUNT`), not
  whole collections.

## 3. Cache Reads Through the Shared Library

Use `IDistributedCache.Get<T>(key, createItem, slidingExpiration, absoluteExpiration)` from
`CasCap.Common.Caching` for cache-aside reads. Do not hand-roll a get, check and set sequence. The
[cached read example](./examples/cached-read.md) shows the read, write and invalidation shape.

The shared implementation:

- Checks the local layer (memory or disk), then Redis, then calls `createItem`.
- Runs `createItem` once per key per process. Concurrent callers wait, then read the stored entry.
- With `DistributedLockingEnabled`, also serialises misses across instances using the root Redlock
  timings. If that lock times out, `createItem` still runs; the caller never receives a false miss.
- Does not cache a `null` result, so a missing source record is fetched again on every call. Cache an
  explicit empty value with a short TTL when absence is frequent and expensive.
- Publishes an invalidation over pub/sub on `Set` and `Delete` so other instances drop their local
  copy when `LocalCacheInvalidationEnabled` is on.
- Counts each local entry as size 1 against `MemoryCacheSizeLimit`. Once the limit is reached, new
  entries are not stored locally and reads fall through to Redis, so size the limit above the
  working set of keys rather than in bytes.

On writes, update the authority first and then `Delete` the cache key. Do not `Set` a value computed
before the write committed; a concurrent reader can repopulate a stale value. Load
[cache patterns](./references/cache-patterns.md) before implementing read-through, write-through,
write-behind or refresh-ahead behaviour, or a cache that is not cache-aside.

### Find Uncached Reads

In `audit` mode, look for reads that should go through the cache but do not:

1. List repeated reads of a database, table store or external API: per request, per message, per
   agent turn, per tick, or inside timers and loops. One-off startup and warm-up reads do not count.
2. Classify the data. Reference data, definitions, configuration and derived summaries that change
   rarely are candidates. Transactional state, such as balances, orders, positions and session
   state, stays uncached unless every write path invalidates it.
3. For each candidate, record the call site, how often it runs, the tolerable staleness, and the
   write paths that would need to delete the key.
4. Check that existing cached reads use `Get<T>(key, createItem, ...)`. A hand-rolled get, then load,
   then `Set` sequence loses the per-key stampede protection.

Query shape (N+1 queries, missing indexes, projections, paging) is database tuning, not caching.
Use the [EF Core skill](../dotnet-efcore/SKILL.md) for EF-backed query tuning; report it separately
rather than hiding a slow query behind a cache.

## 4. Set Expiry Deliberately

- Give every cache-role key an expiry. Choose the duration from how stale the reader can tolerate,
  not only from how often the source changes, and record it in configuration.
- Prefer absolute expiry computed from an injected `TimeProvider`, plus random jitter of about 10%
  so entries written together do not expire together.
- Use sliding expiry only for access-driven working sets such as sessions. Redis has no native
  sliding expiry; the library emulates it, and keeping local and remote copies aligned needs
  `ExpirationSyncMode`, which adds round trips.
- The library rejects a call that passes both sliding and absolute expiry, and an absolute expiry
  already in the past. Validate computed values before the call.
- State keys follow the Redis instructions: `stats` keys carry a 7-day TTL, `series` partitions
  expire at the end of their retention, and `snapshot` hashes have no TTL because they are
  overwritten in place.
- Trim single long-lived streams with `MAXLEN ~` or `MINID` on `XADD`. Never put a TTL on such a
  stream; expiry deletes its consumer groups and pending entries.
- A date-partitioned stream key (`{domain}:stream:{yyMMdd}`) may instead expire as a whole once its
  retention exceeds the longest consumer lag. Set that TTL once per key, for example with
  `ExpireWhen.HasNoExpiry`, rather than issuing an extra awaited command on every append.
- Lock TTLs come from the Redlock profile; see the `leadership-election` skill.

## 5. Produce and Consume Streams

- Name consumer groups as the Redis instructions require. Give each replica a stable, unique
  consumer name, such as the pod name, so pending entries can be attributed and reclaimed.
- Treat delivery as at least once: process, then `XACK`. Make handlers idempotent by entry
  identifier or a business key. Reclaim pending entries from dead consumers with `XAUTOCLAIM`.
- Explicit entry identifiers must be strictly increasing per stream; a duplicate or older identifier
  is rejected.
- Use `CommandFlags.FireAndForget` on `XADD` only for loss-tolerant telemetry.
- Read with a bounded `COUNT` and a blocking timeout tied to the host cancellation token.
- Create groups idempotently at startup (`MKSTREAM`, ignore `BUSYGROUP`). Never destroy a group to
  reset a consumer; that discards every pending entry.

## 6. Place Keys on an Endpoint

Load [topology](./references/topology.md) before adding a Redis endpoint, enabling Sentinel,
changing `maxmemory-policy` or moving a role between endpoints.

- Redlock locks must use an endpoint that never fails over. Asynchronous replication can lose a
  just-granted lock, and the promoted replica then grants it again.
- Streams, consumer groups, hashes and sorted sets replicate and fail over like any other type. A
  failover can lose the last acknowledged writes or acknowledgements, so consumers must already be
  idempotent.
- Match the eviction policy to the roles present. `volatile-lru` evicts only keys with a TTL, so
  cache entries go first and state, streams and locks without a TTL are kept.
- Connect to Sentinel-managed Redis through its `serviceName=` connection string, never through a
  load-balanced address that can reach a replica.
- Give each application sharing an instance its own `RemoteCache.DatabaseId`. A shared database
  mixes key scans, keyspace notifications and any `FLUSHDB` or `DeleteAll` across applications.
  Pub/sub channels ignore the database number, so the library's local-invalidation channel is
  shared by every application on the instance regardless.

`CasCap.Common.Caching` currently opens one connection for the cache, Redlock and any consumer that
reuses it. Named connections are tracked in
[f2calv/CasCap.Common#330](https://github.com/f2calv/CasCap.Common/issues/330). Until then, all roles
share one endpoint; do not open a parallel connection that bypasses the library's registration.

## 7. Validate

Build in Release, then ask before running tests. Prefer deterministic fakes for library behaviour and
an isolated Redis container for integration; never validate against a shared or production instance.

| Scenario | Evidence required |
| --- | --- |
| Concurrent miss on one key | The source is called once; every caller receives the same value. |
| Distributed lock timeout | The value is still returned and stored; no `null` reaches the caller. |
| Write followed by read | The authority changes first and the next read returns the new value. |
| Second instance after a write | Its local copy is invalidated or expires within the documented bound. |
| Absolute expiry | Both the local and remote copies disappear after the deadline. |
| Memory pressure | Only cache-role keys are evicted; state, streams and locks remain. |
| Consumer restart | Pending entries are reclaimed and reprocessing is idempotent. |
| Key format change | Old and new keys are migrated or deliberately orphaned in one change. |

## Diagnose

Trace the symptom in order and stop at the first mismatch:

- **Stale data**: effective key, including `CacheKeyFormat` and database -> `PTTL` -> local copy and
  invalidation subscription -> writer ordering (authority before delete).
- **Missing data**: key format and database -> `TTL` -> `INFO stats` `evicted_keys` and
  `expired_keys` -> `maxmemory-policy` -> whether the source returned `null`, which is never cached.
- **Duplicated processing**: `XINFO GROUPS` and `XPENDING` -> consumer names per replica ->
  acknowledgement placement -> handler idempotency -> recent failover.
- **Expiry events not arriving**: `CONFIG GET notify-keyspace-events` on the primary; the expiry
  subscriber needs both `E` and `x`.

## Maintaining This Skill

- Recheck section 3 when `IDistributedCache`, `DistributedCacheService` or the Redlock cache-miss
  timings change, and keep the example compiling against the current API.
- Replace the single-connection note in section 6 once named connections and Sentinel support ship
  in `CasCap.Common.Caching`, and update the topology reference to match.
- Fold newly verified patterns, such as refresh-ahead or tag invalidation added to the library, into
  the cache patterns reference rather than this file.
- Add each newly diagnosed failure mode to the Diagnose section with the command that exposed it.
- Recheck StackExchange.Redis and Redis server behaviour (Sentinel, field-level hash expiry, stream
  trimming) when their major versions change.
