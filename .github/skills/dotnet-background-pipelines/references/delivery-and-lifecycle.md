# Delivery, Backpressure and Lifecycle

## Capacity and Delivery

| Mechanism | What it provides | What it does not provide |
| --- | --- | --- |
| Bounded channel with `Wait` | Backpressure while full | Persistent storage, bounded payload bytes or bounded pending producers |
| Drop modes | Chosen loss policy when full | Confirmation that every completed write retained its item |
| Multiple readers | Competing consumption | Broadcast or completion ordering |
| `TryComplete` / reader completion | End-of-input signal and eventual buffer exhaustion | Proof all dequeued items finished their side effects |

`TryWrite` returning false may mean full or closed; preserve the application-visible distinction
where required using the broker's state/protocol. With drop modes, a successful write is not a
retention guarantee. If loss is intentional, measure it using supported callbacks/owner logic.
`SingleReader` and `SingleWriter` are promises about actual concurrency, not tuning hints to set
optimistically. FIFO dequeue does not preserve side-effect completion order with parallel readers.

Do not enqueue scoped service objects, request contexts, borrowed buffers or streams whose owner
will dispose them. Prefer immutable bounded payloads or identifiers resolved inside the work scope.
Tie pending admission to request cancellation so disconnected callers do not accumulate indefinitely.

## Supervision

Retain producer and consumer tasks. On a fault, signal peer cancellation and release blocked channel
operations promptly, then await all tasks and surface the original fault through the host boundary.
Do not await `Task.WhenAll` before triggering peer cancellation: one failed consumer can leave a
producer blocked forever on a full queue.

A task-set supervisor can await `Task.WhenAny`, inspect/remove the finished task, and react
immediately to fault or unexpected completion. On normal completion, continue supervising remaining
tasks. On failure, cancel peers, complete admission as appropriate, await cleanup and retain the
failure as failure. Observation/cleanup must not turn a fault into a success-shaped result.

Expected cancellation is distinct from failure only when the owning cancellation was requested.
An unrelated `OperationCanceledException` can indicate a dependency timeout or bug.
`StopApplication` requests shutdown; it does not itself prove a nonzero process exit.
Verify entrypoint exit behavior using the CLI/host contract.

## Graceful Drain Versus Abort

Use separate control for closing admission and aborting execution when graceful drain is required.
Passing the already-cancelled host stopping token to every read/handler aborts rather than drains.
Adapt this distinction explicitly to `BackgroundService.StopAsync` and host shutdown deadlines;
do not detach workers to evade the host's lifecycle.

1. Atomically close admission and stop upstream producers under the broker's protocol.
2. Await producer termination; the designated owner completes the writer after all producers end.
3. Continue awaiting consumers processing buffered and in-flight work using the drain budget.
4. At the deadline, cancel processing, await cooperative cleanup and report unfinished work.
5. A dependency ignoring cancellation can outlive the budget. Report that failure honestly; no
   cancellation API can safely force arbitrary managed work to stop.

Define whether deadline expiry fails the job/process and what can replay unfinished work.
An unpersisted item removed from a channel is lost after process failure unless another authority
can reconstruct it. Do not promise exactly-once processing; use durable delivery plus idempotent
effects when necessary.

Classify interrupted reservations from durable intent, not only a process-local "submitted" flag.
A database commit can succeed while its acknowledgement is lost or cancelled. Before requeueing,
read the authoritative reservation; an unresolved external-mutation intent must not become an
automatic replay merely because the caller never observed successful reservation.

## Retry and Progress

Bound attempts, delay and total processing time. Retrying writes into the same full channel from
all consumers can deadlock. Prefer an established durable retry facility or controlled local
retry within the job's budget. Persist poison work only through an authorized storage contract;
do not silently discard it or retain full sensitive payloads in diagnostics.

Measure queue age, admitted/rejected/dropped counts, active work, failures and progress using bounded
labels. Idle readiness is not proof of progress, but healthy idle/standby must not be marked failed.

For hosted lifecycle details see
[background services](https://learn.microsoft.com/en-us/dotnet/core/extensions/workers).
