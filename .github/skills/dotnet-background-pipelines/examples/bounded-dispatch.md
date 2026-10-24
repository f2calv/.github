# Bounded Dispatch With Explicit Drain

A synthetic host accepts replayable work identifiers and processes them locally. Loss on process
crash is acceptable because the authoritative source can resubmit. This is an illustrative design,
not an executed hosted-service implementation or a durable queue.

## Channel Fragment

```csharp
var channel = Channel.CreateBounded<WorkItem>(new BoundedChannelOptions(32)
{
    FullMode = BoundedChannelFullMode.Wait,
    SingleReader = false,
    SingleWriter = false,
    AllowSynchronousContinuations = false
});
```

Use `System.Threading.Channels`; `WorkItem` is an immutable synthetic payload. Capacity 32 is
only an example, not a recommended fleet default. Two consumers and concurrent producers justify
both `Single*` options being false. Each producer awaits:

```csharp
await channel.Writer.WriteAsync(workItem, admissionToken);
```

There is no unbounded `Task.Run` per request. The ingress owner also bounds concurrent admissions
so waiting producers do not defeat the memory limit. Writer completion is owned centrally, not
performed by whichever request happens to finish first.

## Owner State Machine

| State | Admission | Producers/consumers |
| --- | --- | --- |
| Running | Allowed within bounded limits | All retained tasks supervised |
| Closing | New writes explicitly rejected | Stop/await existing producers; coordinate writers racing closure |
| Draining | Writer completed after producers finish | Consumers finish buffered and in-flight work |
| Aborting | Closed | Cancel execution; await cleanup; report remaining/replayable work |
| Stopped or failed | Closed | All owned tasks observed; final result retained |

The owner uses a separate drain/abort token rather than immediately cancelling every consumer when
host shutdown begins. A failure transitions directly to abort and wakes blocked readers/writers.
The first observed fault initiates cancellation **before** awaiting all peers.

For each dequeued item, create an async scope, resolve the handler and await its side effect before
releasing the scope. A failure after dequeue does not put the item back automatically. Apply the
documented bounded retry/replay policy; do not claim durable acceptance from channel insertion.

## Acceptance Cases

Use deterministic gates to stop consumers and control completion. Do not rely on millisecond sleeps.

| Case | Expected observation |
| --- | --- |
| 32 queued items with consumers gated | Next write stays pending until capacity is released |
| Pending writer cancelled | Admission ends as cancellation; no later ghost enqueue |
| Consumer faults while producer is blocked | Supervisor wakes/cancels producer and reports fault without hanging |
| One producer finishes before another | Channel stays open until the designated owner closes it |
| Graceful shutdown with buffered/in-flight work | Admission closes; both kinds of work finish before successful stop |
| Drain budget expires | Abort requested, unfinished work reported, cleanup awaited |
| Two readers finish at different speeds | No guarantee of completion order; each effect follows idempotency policy |
| API and worker moved to separate processes | Validation rejects in-memory delivery as a connection between them |
| Crash after dequeue | Recovery relies on the named authoritative source, not the channel |

The final test requires an isolated crash/restart fixture if implementation claims recovery.
Documentation and ordinary channel unit tests alone cannot prove that guarantee.
