# Lease Lifecycle

Bind leader-only work, schedules and delivery to a single lease lifetime, and protect beyond the lease.

Use the lifecycle **contend -> acquire -> start -> active -> stop -> release -> contend**.
Lease loss, failure and host shutdown must all leave the active path.

1. Await acquisition with the host cancellation token. Inspect `IsAcquired`; contention is a
   normal standby outcome, not permission to execute leader-only work.
2. Retain the acquired `IRedLock` for the entire protected lifetime with `await using` or equivalent
   guaranteed asynchronous disposal. Do not acquire in a helper that disposes before work starts.
3. Start a distinct ownership run with a linked cancellation source. Pass its token through every
   timer, delay, I/O operation, connection attempt and child loop. Retain and await child tasks;
   fire-and-forget work must not outlive its lease. Supervise only enabled, required loops: an
   optional loop that immediately returns when disabled must not prematurely finish a healthy group.
4. Check that ownership is still valid during long-lived work using the installed library's
   supported state/signals. A single `IsAcquired` check at entry is insufficient for an unbounded
   worker. Polling, if necessary, has a detection delay and is not a safety proof.
5. On observed loss, withdraw active ownership, cancel the run, stop side effects and close external
   sessions. Await cleanup before starting another run. On graceful shutdown, stop the worker
   while the lease is still held, then dispose it.
6. Specify what happens when cleanup cannot finish within the shutdown budget. Releasing a valid
   lease while old work continues permits overlap; an already-lost lease cannot exclude a new
   owner. Use the host's explicit failure policy rather than reporting a clean release.
7. Clear transient state on every exit path, including failed startup and disposal. Reacquire a
   fresh lease before restarting. Preserve requested cancellation; distinguish standby contention,
   lease loss, Redis failure and business-worker failure in logs and recovery behavior.
8. Avoid hot spinning after a failed acquisition, immediately completed worker or failure. Use
   bounded, cancellation-aware backoff appropriate to the acquisition wait and retry policy;
   retry only failures for which recovery is intended and observable.
9. Guard late callbacks and cleanup by ownership-run identity so an old run cannot mark a new run
   inactive or publish stale state.

## Coordinated Schedules and Delivery

- Use [cron scheduling](../../dotnet-cron-scheduling/SKILL.md) for expression dialects, UTC cursors,
  startup/manual triggers, coalescing and reusable timing mechanics; keep ownership here.
- For several independent long-lived schedules sharing one lease, defer starting them until the
  ownership callback is invoked. `Task.WhenAll` alone does not cancel siblings when one faults.
  Prefer existing framework supervision where it fits: `Parallel.ForEachAsync` with one execution
  slot per schedule cancels siblings on an unhandled failure and awaits them. The default
  CPU-bounded parallelism can starve long-lived schedules, so size the slots to the schedule count.
- Preserve the application's deliberate per-job/per-message recovery policy separately from fatal
  ownership-run failures. Cancellation must escape those recovery catches, not emit a failure
  event, send an error notification or begin another side effect under the old token.
- Pass the ownership token through success/failure sinks, enqueue wrappers and fallback delivery,
  not just the main operation. Check cancellation before dispatching APIs without native
  cancellation; await an already-dispatched operation rather than abandoning it with `WaitAsync`.
- Do not infer exactly-once delivery from atomic dequeue. Destructive dequeue before processing
  can lose work on cancellation or crash, while retrying an externally accepted operation can
  duplicate it. Keep delivery/acknowledgement and idempotency changes explicit and separately
  evaluated; document existing semantics rather than silently requeueing uncertain outcomes.
- Use injected clocks and explicit startup/cleanup gates to test multi-loop cancellation. Keep
  UTC test timestamps offset-aware across successive runs; converting an unspecified `DateTime`
  to `DateTimeOffset` can accidentally introduce workstation-local offsets.

In the inspected RedLock.net 2.3.2 API, `IRedLock` exposes `IsAcquired`, `Status`,
`InstanceSummary` and `ExtendCount`; status values include `Unlocked`, `Acquired`, `NoQuorum`,
`Conflicted` and `Expired`. No loss callback was identified in that API inspection. Verify
current semantics rather than inventing an event, treating an acquisition failure as a renewal
failure, or assuming `ExtendCount` proves that ownership is still valid now.

## Safety Beyond the Lease

Redlock is coordination, not exactly-once execution or a downstream fencing token. A paused owner
can resume after its lease has expired and another replica has acquired ownership. Redis topology,
failover, clock behavior and network partitions affect the guarantee.

For operations that cannot tolerate stale owners, use downstream-enforced fencing where supported,
plus idempotency or transactional checks as appropriate. A fencing token must be monotonically
ordered across owners and enforced by the resource accepting writes; a process-local generation,
GUID or heartbeat is not such a token. Gate side-effect entry points as well as the outer loop,
but do not present a check immediately before a write as atomic ownership enforcement.
