---
name: dotnet-background-pipelines
description: 'Design, implement, audit or troubleshoot .NET background producer/consumer pipelines, System.Threading.Channels, bounded queues, backpressure, worker concurrency, completion, cancellation, draining, fault supervision and durable-delivery boundaries. Use for brokers and queued background processing, not only hosted-service registration or distributed leader election.'
argument-hint: '[design|apply|audit|diagnose] [pipeline or worker]'
user-invocable: true
---

# .NET Background Pipelines

Treat a queue as an admission, ownership and lifecycle contract, not just a collection between tasks.

## Resources and Boundaries

- Load [delivery and lifecycle](./references/delivery-and-lifecycle.md) before changing completion,
  concurrency or shutdown, and the [bounded pipeline example](./examples/bounded-dispatch.md)
  for concrete settings, supervision steps and failure cases.
- The [C# instructions](../../instructions/dotnet.csharp.instructions.md) own cancellation,
  task/disposal and hot-path logging conventions. Use
  [DI](../dotnet-dependency-injection/SKILL.md) for scopes,
   [modular monolith](../patterns-monolith-modular/SKILL.md) for role/host contracts and
  [leadership election](../leadership-election/SKILL.md) for replica ownership.
- Use [Redis data access](../redis-data-access/SKILL.md) for Redis streams/consumer groups,
  [gRPC](../dotnet-grpc/SKILL.md) for remote streaming, transport liveness and RPC acknowledgements,
  [EF Core](../dotnet-efcore/SKILL.md) for transaction/outbox boundaries and
  [performance](../dotnet-performance/SKILL.md) only for measured hot paths.
- Official [Channels documentation](https://learn.microsoft.com/en-us/dotnet/core/extensions/channels)
  explains bounded modes and reader/writer APIs; verify the target runtime.

## Workflow

1. Trace every producer, queue instance, consumer and owner through registration, runtime roles and
   completion. Distinct processes do not share an in-memory queue. Confirm API and worker roles
   actually coexist when delivery relies on process-local state.
2. Record accepted input, acknowledgement point, durability requirement, capacity, payload size,
   expected throughput, concurrency and ordering. Ask before changing loss, latency or admission
   behavior; do not pick an arbitrary capacity or drop mode as an optimization.
3. Search existing brokers/dispatchers before introducing another abstraction. Choose in-memory
   channels only when restart/crash loss is acceptable or an authoritative source can replay work.
   An accepted HTTP response must not imply durable acceptance unless persistence has committed.
4. Design bounded admission: wait/reject/drop policy, producer cancellation, shutdown races and
   explicit metrics. Include work already processing and suspended producers in resource budgets.
5. Define processing ownership, retries and idempotency. Multiple channel readers compete for
   items; they do not broadcast. Dequeue is not acknowledgement or automatic redelivery.
6. Wire lifecycle from the reference: stop admission, stop producers, complete once, drain or abort
   within the approved deadline, supervise faults, await all tasks and release scopes/resources.
   A finite pipeline and a daemon have different normal-completion contracts.
7. Use per-operation scopes and propagate cancellation into dependency calls. Bound retry queues
   and delayed work as well as the primary channel; retries must not deadlock their own consumers.
8. Update callers, readiness/progress, queue-age/depth metrics and documentation together. Keep
   message contents and user identifiers out of logs, traces and metric labels.

## Validation and Reporting

With approval, run isolated deterministic tests using gates/fake clocks rather than timing sleeps.
Cover full capacity, pending writers, cancellation, producer failure, consumer failure, duplicate
delivery, shutdown races, normal drain and deadline expiry. Verify actual side effects and task
completion, not merely that a cancellation token was signalled.

Report admission/delivery guarantees, ordering, ownership, fault and shutdown behavior, measured
resource limits, checks executed and any untested crash/restart assumptions. Do not run live
workers, load tests or change replica counts without separate authorization.

## Maintaining This Skill

Apply the shared [customization feedback loop](../../instructions/workflow.instructions.md#maintaining-conventions)
when using this skill; the triggers below include newly learned topics, not only version drift.

- Incorporate verified admission, supervision or delivery lessons into the relevant workflow/reference;
  extend the state-machine example and acceptance cases for reusable failure/recovery scenarios.
- Revisit channel option semantics and host background-exception behavior when .NET changes.
- Update acceptance cases when admission, retry, drain deadlines or durability contracts change.
- Keep broker-specific acknowledgement and recovery procedures in the owning transport skill.
