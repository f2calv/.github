# Redis Topology

Load this reference before adding a Redis endpoint, enabling Sentinel, changing eviction or
persistence, or moving a key role between endpoints. Hostnames below are placeholders.

## Role Requirements

| Role | Eviction | Persistence | Failover |
| --- | --- | --- | --- |
| Cache | Allowed; evict first | Optional | Helpful, not required: loss costs a refill |
| State | Never | AOF recommended | Recommended |
| Stream | Never | AOF recommended | Recommended; consumers must be idempotent |
| Lock | Never | AOF, or delayed restart | **Never**: use a non-failover endpoint |

## Layouts

| Layout | Assessment |
| --- | --- |
| One standalone instance for every role | Simplest. No failover: a restart or node loss interrupts every role until Redis returns. |
| One Sentinel-managed instance for every role except locks, plus a small standalone instance for locks | Recommended. Cache, state and streams fail over; locks keep single-owner safety. |
| One Sentinel-managed instance for every role, including locks | Accepts duplicate lock owners on failover. Only acceptable with downstream fencing or idempotent leader work. |
| Separate cache-only and state instances | Justified only when the roles need different memory sizes or persistence. Eviction alone does not require a split. |

`CasCap.Common.Caching` uses one connection for every role today. Named connections, which the
recommended layout needs, are tracked in
[f2calv/CasCap.Common#330](https://github.com/f2calv/CasCap.Common/issues/330).

## Sentinel

- Run at least three Sentinel processes on separate nodes with a quorum of two, so one node loss
  neither blocks nor falsely triggers a failover.
- Connect with the Sentinel endpoints and the monitored service name. StackExchange.Redis then
  follows the current primary across failovers:

  ```text
  sentinel-0.example.com:26379,sentinel-1.example.com:26379,sentinel-2.example.com:26379,serviceName=mymaster,abortConnect=false
  ```

- Never connect through a load-balanced address or Kubernetes Service that can route to a replica.
  Writes then fail intermittently with `READONLY`. `XADD` and `XREADGROUP` are both write commands,
  so stream producers and consumers fail first; that symptom is a routing fault, not a stream
  limitation.
- Administrative commands (`FLUSHDB`, `SCRIPT LOAD`, `SCAN` for maintenance) must target the current
  primary, not the first endpoint the client discovered.
- Replication is asynchronous. A failover can lose the last writes and acknowledgements that the
  primary accepted but had not yet replicated. `WAIT` narrows that window for individual writes but
  does not make Redis strongly consistent.

## Eviction

Set `maxmemory` below the container memory limit, leaving headroom for replication buffers and the
copy-on-write growth of an AOF rewrite or snapshot fork.

| `maxmemory-policy` | Effect | Use for |
| --- | --- | --- |
| `noeviction` | Writes fail with `OOM` when full | State, stream or lock instances without cache keys |
| `volatile-lru` | Evicts least-recently-used keys that have a TTL | Shared instances: cache keys go, state without a TTL stays |
| `allkeys-lru` | Evicts any key | Cache-only instances |

Under `volatile-lru`, an instance full of keys without a TTL behaves like `noeviction`. Alert on
`used_memory` approaching `maxmemory` and on `evicted_keys` rising.

Without `maxmemory`, no eviction policy ever applies: Redis grows until the container's memory
limit and is then killed, which loses every role on the instance at once. Always set it explicitly.

## Persistence

- Enable AOF with `appendfsync everysec` for state and streams. At most about one second of writes
  is lost on a crash.
- A cache-only instance may run without persistence; a restart empties it and readers refill it.
- For a lock instance, either persist with AOF or delay the restart beyond the longest lease TTL, so
  a restarted, empty instance cannot grant a lock that a live owner still believes it holds.

## Databases

Numbered databases share one instance's memory, eviction policy, persistence and failover. They
separate key namespaces, not workloads. Redis Cluster supports only database 0, so prefer key
prefixes for new separation.

## Keyspace Notifications

- `notify-keyspace-events` is per-node configuration. Set it on every node, including replicas that
  may be promoted, through the server configuration rather than a runtime `CONFIG SET`.
- `__keyevent@<db>__:expired` subscriptions need `E` (key-event channel) and `x` (expired events).
  `KEh`, for example, emits hash events but no expiry events.
- Replicas do not expire keys themselves; they wait for the primary's deletion. Subscribe on the
  primary.
- Events are fire-and-forget. Events raised while a subscriber is disconnected, including during a
  failover, are lost. Treat them as hints and never as the only trigger for correctness.

## Moving a Role Between Endpoints

Moving keys between endpoints is a key migration. Plan it explicitly:

- **Cache**: switch the connection; the new endpoint fills on demand.
- **State**: copy or rebuild before switching readers, then switch writers.
- **Streams**: drain consumers on the old endpoint, recreate groups on the new endpoint, then switch
  producers. Do not run both endpoints as one logical stream.
- **Locks**: treat as an ownership migration. Old and new replicas on different endpoints can both
  lead; follow the `leadership-election` skill's key-migration guidance.
