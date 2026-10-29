---
name: dotnet-cron-scheduling
description: 'Create, extract, audit or troubleshoot .NET cron/crontab scheduling: Cronos expressions, UTC and time zones, startup runs, hourly jobs, missed-occurrence coalescing, non-overlap, manual triggers, injected clocks, cooperative deadlines and reusable schedule runners. Use for scheduled background services and periodic reconciliation; use leadership-election for distributed ownership and dotnet-background-pipelines for delivery guarantees.'
argument-hint: '[apply|audit|diagnose] [schedule or worker]'
user-invocable: true
---

# .NET Cron Scheduling

Treat a cron expression as an occurrence selector, not a durable job queue or an ownership mechanism.
Keep timing mechanics reusable and business policy in the consuming application.

## Authorities and Boundaries

- Follow [C# instructions](../../instructions/dotnet.csharp.instructions.md) for cancellation,
  injected time, disposal and logging, and
  [configuration instructions](../../instructions/dotnet.configuration.instructions.md) for binding
  and startup validation.
- Use [leadership election](../leadership-election/SKILL.md) when replicas must coordinate.
  Do not duplicate its lease lifecycle, Redis configuration or downstream fencing rules.
- Use [background pipelines](../dotnet-background-pipelines/SKILL.md) for durable admission,
  idempotency, acknowledgement and shutdown. A timer does not supply these guarantees.
- Use [CLI applications](../dotnet-cli/SKILL.md) for finite administrative commands and
  [EF Core](../dotnet-efcore/SKILL.md) for persisted requests, claims and transactional reconciliation.
- Ask before builds/tests, live job execution, deployments or new chargeable work. Implementing
  a timer does not authorize running the operation it schedules.

## Workflow

### 1. Establish the Schedule Contract

Inspect the worker, registration, runtime roles, clock, configuration, current scheduler package,
manual entrypoints and tests. Search shared libraries before adding another timer loop.

Resolve these choices explicitly:

| Concern | Contract |
| --- | --- |
| Dialect | Scheduler/parser and version; five-field minutes or explicitly enabled seconds |
| Zone | UTC by default, or an explicitly configured named business time zone and DST policy |
| Startup | No immediate run, or one run after ownership acquisition before regular occurrences |
| Missed runs | Coalesce, catch up with a defined bound, or persist each occurrence durably |
| Overlap | Sequential per job; define how manual requests interact with scheduled runs |
| Ownership | Every replica, one elected owner, or independently owned partitions |
| Failure | Per-run recoverable failures versus faults that stop the owned worker |
| Deadline | Cooperative timeout, awaited cleanup and host termination policy |
| Recovery | Restart/failover behavior and whether an interrupted run resumes or starts anew |

Do not silently replace a fixed-delay interval with wall-clock cron: "one hour after completion"
and "at minute zero every hour" are different contracts.

### 2. Parse and Validate Once

With Cronos, the standard five fields are:

```text
minute hour day-of-month month day-of-week
0      *    *            *     *              hourly at minute zero
*/15   *    *            *     *              every fifteen minutes
```

Use `CronExpression.Parse(expression)` for the standard format. A six-field expression requires
explicit `CronFormat.IncludeSeconds`; never guess the dialect from a field count.
Validate configured expressions at startup with the same parser/format used at runtime.
Define behavior when an expression has no future occurrence.

Do not assume Unix, Quartz, cloud scheduler and Cronos expressions are interchangeable.
Verify day-of-week numbering, simultaneous day-of-month/day-of-week constraints and supported
operators against the selected parser. Never import another dialect's year field or special
characters without verification.

Use offset-aware timestamps and select occurrences in UTC unless business requirements demand
another zone. For local schedules, verify skipped and repeated DST times using the actual parser;
do not emulate zones by adding a fixed offset.

### 3. Reuse Sequential Timing Mechanics

The current shared-services checkout exposes `CasCap.Common.Services.CoalescingScheduleRunner`:

- `RunAsync(cron, timeProvider, callback, cancellationToken)` selects UTC occurrences strictly
  after its cursor, awaits each callback and coalesces missed occurrences after completion.
- `GetNextOccurrence(cron, cursor)` performs the same exclusive UTC selection.
- `RunWithTimeoutAsync(operation, timeout, timeProvider, cancellationToken)` cancels a cooperative
  operation on deadline and awaits it before returning or reporting timeout.

Verify these APIs in the consumer's actual project/package graph. Checkout availability does not
prove that a published package contains them; preserve conditional Debug source references and
report any publication prerequisite.

Keep the reusable runner free of application jobs, storage clients, UI state, deployment coordinates
and Redis ownership. Avoid extracting a broad scheduler framework for one callback.
When moving an existing runner, migrate its real consumers and regression coverage together;
do not leave a second copy or compatibility wrapper.

Use injected `TimeProvider` for occurrence selection, delays and deadlines. Bound long delays to
the platform timer's supported range, re-check wall-clock time after waking, and check cancellation
before invoking the callback. A callback fault must remain observable.

### 4. Compose Startup, Manual and Distributed Execution

Start leader-only schedules inside the ownership callback, never before acquisition.
An immediate startup run should also be inside that boundary; a standby becoming leader must
perform the required recovery run. Cancellation must stop and await all schedules before release.

For several long-lived schedules, use the existing supervised lifecycle rather than detached tasks
or CPU-limited scheduling that can starve some loops. Keep one schedule's cursor independent of
the others. Follow the leadership skill for child-fault supervision and lease-loss handling.

An administrator request may reach a standby replica. If it must survive disconnects/restarts,
persist an authorized request and let the owner claim it; a process-local signal is insufficient.
Coalesce repeated requests when the domain permits it, and serialize manual and scheduled
execution through the same authoritative claim path. Return durable acceptance separately from
successful completion.

For reconciliation, compare authoritative source state with durable work/results, not transient
queue contents. Only a complete successful inventory plus source revalidation can authorize
absence-based cleanup. Partial listings, permission failures and network errors are not deletions.
Fence cleanup against active writers so stale processing cannot republish removed results.

Scheduling must not reset attempt limits, replay uncertain external submissions, enable paid
processing or regenerate unchanged results implicitly. Those are application-owned decisions.

### 5. Verify the Real Timing Contract

With approval, use fake clocks and explicit completion/timer-registration gates. Avoid fixed sleeps
and arbitrary `Task.Yield` counts as evidence that the next timer exists.

Cover:

- Five-field parsing, rejected invalid dialects and startup validation.
- Exclusive cursors at an exact boundary, nonzero offsets and any configured DST behavior.
- Startup execution, next regular occurrence and reacquisition.
- Slow callbacks spanning several occurrences: no overlap and the chosen coalescing/catch-up rule.
- Independent schedules, manual/scheduled contention and repeat-safe durable request handling.
- Cancellation during a delay/callback, callback faults and awaited timeout cleanup.
- Cancellation-ignoring callbacks: the wrapper must not abandon work or report clean completion.
- Restart, expired claims and stale-owner writes where durable/distributed execution is involved.

Build every retained target framework when extracting into a multi-targeted library and validate
the actual consumer. Distinguish fake-clock timing tests, database race tests and observed live
failover; none substitutes for the others.

Report the expression/dialect, zone, startup and missed-run policies, overlap boundary,
ownership/fencing, deadline behavior, executed checks and deployment/publication prerequisites.

## Maintaining This Skill

- Recheck parser semantics and clock/timer limits when upgrading Cronos or .NET.
- Keep shared API guidance aligned with the actual retained frameworks and published availability.
- Fold reusable startup, coalescing, manual-trigger and deterministic-clock lessons into the
  relevant section; keep application schedules and operational incidents in their own repositories.
- Link lifecycle, leadership and delivery authorities rather than copying their rules.
