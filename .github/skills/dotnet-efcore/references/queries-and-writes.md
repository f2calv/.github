# Queries and Writes

## Read Queries and Performance

1. Trace the LINQ query to materialization. Apply authorization/tenant/time predicates, projection,
   deterministic ordering and result limits in SQL before `ToListAsync`, `AsEnumerable` or other
   client-side processing. Keep text/binary payload sizes bounded in the projection where needed;
   `Take` bounds rows, not row width.
2. Use DTO/scalar projections for read contracts and `AsNoTracking` for read-only entity queries.
   A projection containing entity instances can still track them. Use tracking when the operation
   intends to modify those entities; use identity-resolution variants only when their semantics
   and cost are useful.
3. Define deterministic ordering with a unique tie-breaker before paging/limiting. Prefer keyset
   pagination for sequential large histories; retain offset paging when random page access is an
   actual requirement. Bind cursors to the effective tenant/filter/order, not a global row list.
4. Check N+1 queries, lazy loading, repeated materialization and overly broad `Include` graphs.
   Prefer explicit projections; choose single versus split queries from cardinality, round trips
   and consistency requirements rather than enabling a global switch to hide a warning.
5. Inspect translation using `ToQueryString` where supported and sanitized command diagnostics.
   Never solve a translation failure by pulling an unbounded table into memory. Confirm
   provider-specific methods execute server-side and maintain the expected null/culture semantics.
6. Fix query shape, indexing and result volume before adding caching, raw SQL or compiled queries.
   Parameterize dynamic query values rather than building new constant-shaped expression trees
   that defeat query/plan caching. Compiled queries and models need measurements and version checks.
7. Measure representative latency, round trips, rows/bytes and allocations. Database execution
   plans require separate access approval; `EXPLAIN ANALYZE` executes the statement and can be
   expensive or mutating. Never place user/tenant values in query tags, metric labels or logs.

Official guidance:
[efficient querying](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying),
[tracking](https://learn.microsoft.com/en-us/ef/core/querying/tracking),
[pagination](https://learn.microsoft.com/en-us/ef/core/querying/pagination),
[single/split queries](https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries),
[diagnosis](https://learn.microsoft.com/en-us/ef/core/performance/performance-diagnosis).

## Writes and Conflict Handling

- Let a normal `SaveChangesAsync` transaction provide atomicity for one save where the provider
  supports it. Use an explicit transaction for a real multi-command invariant, not every write.
  Keep transactions short and avoid holding database locks across unrelated remote calls.
- Sharing one context preserves tracking and dependency ordering, not atomicity across several
  `SaveChangesAsync` calls. Persist an event and its required derived state within the agreed
  transaction, or define and test replay/recovery for partially completed projection work.
- Inspect the context's default tracking behavior before read-modify-save operations. Under a
  global no-tracking default, use an explicitly tracked query or a deliberate attach/update path;
  mutating a detached object and calling `SaveChangesAsync` can silently write nothing. Verify
  persisted values, not just the absence of an exception.
- Use database constraints as the final authority for uniqueness. A read-before-insert check can
  improve UX but cannot prevent races. Translate only the recognized provider error/constraint
  for an expected conflict; do not treat connectivity, nullability or unrelated FK failures as
  duplicates, and do not leak exception details.
- Configure an optimistic concurrency token when lost-update detection is required. Handle
  `DbUpdateConcurrencyException` with the agreed conflict/reload/merge policy. A revision property
  is not an EF concurrency token unless configured, and insert uniqueness errors are a different
  failure path.
- Retry transient failures only using the provider's supported execution strategy around the
  complete atomic unit. Explicit transactions must cooperate with that strategy. A retry after an
  unknown commit outcome can duplicate effects; define idempotency before retrying mutations.
- `ExecuteUpdate`/`ExecuteDelete` execute immediately without tracked `SaveChanges` processing.
  They bypass tracking-based hooks/concurrency handling and can leave tracked instances stale.
  Apply scope and explicit concurrency predicates, verify affected-row counts and transaction
  boundaries, and preserve auditing/soft-delete rules.
- Do not copy detached DTOs into `Update(entity)` indiscriminately. Authorize the record, whitelist
  mutable fields, preserve concurrency values and avoid marking unrelated columns modified.
- Propagate cancellation and dispose contexts/transactions asynchronously. Cancellation is not
  success and, after a write begins, is not proof that the database did not commit.

Official guidance:
[transactions](https://learn.microsoft.com/en-us/ef/core/saving/transactions),
[concurrency](https://learn.microsoft.com/en-us/ef/core/saving/concurrency),
[connection resiliency](https://learn.microsoft.com/en-us/ef/core/miscellaneous/connection-resiliency),
[bulk updates/deletes](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete).

## PostgreSQL Locks and Raw SQL

- Use provider-native locks only when a proven invariant needs serialization beyond the selected
  constraints/isolation/concurrency mechanism. Locking in one code path does nothing for another
  writer that does not participate; a process-local lock does not coordinate replicas.
- Distinguish transaction-level advisory locks from session-level locks. Transaction locks end
  with the transaction; session locks survive transaction rollback and require release on the
  same physical session. Keep acquisition, protected SQL and release on the owning open connection.
- Do not acquire a session lock on one pooled connection then execute writes through a new factory
  context/connection. Bound lock waits, preserve cancellation, release in `finally`, and verify
  failure/reconnect behavior before returning a connection to the pool. Do not treat provider
  pool reset as the application's lock-ownership protocol.
- Keep raw SQL parameterized with the appropriate EF/Npgsql APIs. Interpolation into an ordinary
  string passed to a raw API is not parameterization. Dynamic identifiers cannot be value
  parameters: use a strict allowlist and provider quoting, never caller concatenation.
- When EF and direct Npgsql commands share an invariant, verify they share the intended physical
  connection and transaction and have explicit ownership/disposal. Raw commands bypass EF
  tracking, query filters and interceptors; preserve tenant, revision and audit predicates.
- Review SQL/schema references whenever mappings or migrations change, and test affected-row
  checks, competing writers and lock cleanup with the production provider.

Official guidance:
[EF SQL queries](https://learn.microsoft.com/en-us/ef/core/querying/sql-queries),
[Npgsql commands](https://www.npgsql.org/doc/basic-usage.html),
[PostgreSQL advisory locks](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS).

## Database, Cache and Event Boundaries

- Identify the authoritative store and required freshness. Keep cache mechanics in the
  [Redis data-access skill](../../redis-data-access/SKILL.md); do not hide an inefficient query
  behind a new cache or keep tracked entities alive in cache entries.
- Commit authoritative state before invalidating/updating derived caches. Account for racing
  readers, stale repopulation and all writer paths; a cache outage must not turn an uncommitted
  mutation into apparent success.
- For revision-qualified reads, define how the revision and payload are read consistently. A
  double-read/retry protocol needs bounds and explicit failure behavior; it is an application
  consistency choice, not a substitute for a database concurrency predicate.
- A database commit and Redis write or event publication are not one atomic transaction. If the
  contract requires durable downstream effects, inspect an existing outbox/idempotent consumer
  pattern before adding retries; do not invent distributed transaction guarantees.
