# Read/Write Separation Without Event Sourcing

A synthetic inventory service owns an item's quantity and revision. Queries return a bounded
stock-card DTO. Commands authorize a quantity change, check the expected revision and preserve
nonnegative quantity. The authoritative state is a normal database row, not an event stream.

This is a transaction/consistency walkthrough, not executable application code or a migration
script. All identifiers are synthetic. Adapt the existing EF mappings, concurrency token and
service boundaries rather than adding a framework.

## Start With a Query Projection

The query filters by the trusted tenant and item ID, then projects only item ID, quantity and
revision before materialization. A list query additionally has deterministic ordering and a limit.
Neither query exposes a tracked entity graph or changes stock.

The command loads the authorized row with tracking, validates the change and expected revision,
increments the revision, and calls `SaveChangesAsync`. Configure revision as a concurrency token
if using EF's optimistic concurrency path; merely incrementing a numeric property is insufficient.

One database and separate command/query methods already provide useful responsibility separation.
A separate persisted stock-card table is unnecessary unless an actual read requirement justifies it.

## Option A: Transactional Persisted Stock Card

If the application needs a stock-card table with immediate consistency, an illustrative command is:

```text
Create one context for this unit of work.
Load item for the authorized tenant; validate expected revision and quantity.
Stage the authoritative quantity/revision change.
Stage the matching stock-card quantity/revision in the same context.
SaveChangesAsync once; let the provider transaction commit both changes.
Return the committed result/version only after the save succeeds.
```

With two saves or direct SQL, explicitly enlist all commands in one transaction. Sharing a
context is not enough. An optimistic conflict or stock-card failure fails the command and leaves
neither table partly updated.

| Before | Accepted command | After commit |
| --- | --- | --- |
| Authority: quantity 12, revision 7 | Set quantity 9 with expected revision 7 | Authority: 9, revision 8 |
| Stock card: quantity 12, revision 7 | Same atomic unit | Stock card: 9, revision 8 |

Another command still expecting revision 7 conflicts. It cannot overwrite revision 8 silently.
Verify the result from a new context rather than inspecting the caller's tracked object.
Reads through a lagging replica/cache still need an explicit read-your-write policy.

## Option B: Eventual Stock Card With Full Snapshots

Choose this only when delayed reads are acceptable or independent processing is required:

```text
Command transaction:
  Update authority to quantity 9, revision 8.
  Persist an outbox record with event ID, tenant/item, revision 8 and quantity 9.
  Commit both, then return the committed revision.

Existing delivery process:
  Deliver the committed outbox payload with retry.

Projection transaction:
  Serialize updates for the tenant/item using the existing concurrency mechanism.
  Check event identity and stored source revision.
  Apply the accepted full snapshot and record its deduplication/checkpoint state.
  Commit before acknowledging delivery.
```

The outline assumes an existing durable delivery mechanism; it does not supply one. A process
crash after authority commit must not lose the notification, and competing consumers must not
regress a newer stock card.

Here each payload is a **complete snapshot**, so revision 9 can supersede revision 8. If revision 8
arrives afterward, the consumer records/acknowledges the handled stale delivery without regressing
the card. A duplicate event changes nothing. Delete/tombstone handling must preserve enough
ordering state that an older delayed snapshot cannot recreate a deleted card.

That rule is unsafe for incremental deltas. If revision 8 means “subtract 3” and revision 9 means
“add 2”, applying 9 and ignoring 8 loses a change. Delta processing needs contiguous order or a
documented gap-recovery mechanism; do not copy full-snapshot behavior blindly.

The command returns revision 8 while the stock card may still show 7. The API must either document
that lag, read authoritative state for confirmation, or implement a bounded wait for the required
checkpoint. A timeout reports pending/unavailable according to the contract, not invented freshness.

## Acceptance Cases

| Case | Required outcome |
| --- | --- |
| Query after a command | Visibility matches the selected transaction/replica/cache contract |
| Two commands expect revision 7 | One accepted update, one explicit conflict |
| Transactional stock-card save fails | Authority and stock card both remain unchanged |
| Crash after command commit, before delivery | Durable change remains available for recovery |
| Crash after projection commit, before acknowledgement | Redelivery does not change the result twice |
| Two projection consumers race | Stored revision never regresses and deduplication remains consistent |
| Full snapshot 9 arrives before 8 | Card stays at 9 after both are handled |
| Incremental event has a version gap | Explicit wait/recovery behavior, not silent dropping |
| Authorized tenant differs | No cross-tenant query, update, checkpoint or deduplication leakage |
| Rebuild requested | Defined authoritative source, concurrent-write/cutover policy and operator approval |

Audit records are not automatically sufficient to rebuild the projection. If history is incomplete
or retention has removed required records, use a supported authoritative snapshot/rebuild process
or report the limitation. Read/write separation, an outbox and this derived table still do not make
the application event-sourced.

Run provider-backed transaction/concurrency tests only with approval and isolated resources.
No PostgreSQL, transport or crash-recovery test result is claimed by this walkthrough.
