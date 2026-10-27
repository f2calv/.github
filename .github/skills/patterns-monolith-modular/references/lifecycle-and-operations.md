# Worker Lifecycle and Role Operations

## Supervise Selected Background Work

Trace the existing hosting mechanism before adding another dispatcher. Distinguish:

- A feature registered with DI.
- A feature selected by configuration.
- An implementation actually launched by the host.
- A worker holding ownership and making observable progress.

In the inspected shared `IBgFeature`/`AddFeatureFlagService` pattern, the dispatcher starts all
registered matching implementations plus designated always-enabled work concurrently. Selection
deduplication does not deduplicate implementations: two matching registrations can start two loops.
Verify the consumer package version before relying on these semantics.

No-match selection and unexpected completion of all workers are explicit failure conditions in
that implementation. A finite worker returning is not automatically equivalent to successful host
completion. The dispatcher links cancellation, requests shutdown on faults and awaits remaining
workers. Do not infer a nonzero **process exit code** merely from `StopApplication`; verify the
outer host's exception handling, `BackgroundServiceExceptionBehavior` and exit-code path.

Keep the existing lifecycle implementation when it fits. Do not copy its internals into each
application or register an alternative dispatcher alongside it.

## Co-Hosted Work and Dependency Lifetimes

- Retain and await owned tasks; exceptions cannot be lost in fire-and-forget calls.
- Propagate the host/ownership cancellation tokens through nested work and waits. Wait for cleanup
  before disposing scopes, connections and linked cancellation sources.
- Scope database contexts and scoped dependencies per unit of work, not as fields on long-lived
  singleton workers. Reuse the EF Core skill for factory/transaction mechanics.
- Define failure policy: which worker faults should stop the process versus be handled with a
  bounded retry, and what evidence establishes progress after recovery.
- Do not assume registration order means readiness order. Establish explicit startup prerequisites
  without blocking startup on an infinite worker loop.
- Avoid unbounded channels, queues, retries and concurrency. Co-hosted roles compete for CPU,
  memory and external quotas; use existing backpressure and capacity controls.

## Finite Jobs Versus Daemons

Prefer an explicit finite mode when successful completion must terminate the container.
Build only the dependencies the command needs, execute the job, return a meaningful exit status,
and skip ordinary server startup/endpoints. An external schema migrator is one such role; its
database privileges and rollout order stay separate from the runtime.

If a finite worker uses the shared background dispatcher, implement the verified shutdown contract.
In the inspected implementation it must request host shutdown before its final completion; otherwise
completion of all workers is treated as unexpected. Avoid racing startup/shutdown notifications.

Do not combine a “stop the host on completion” job with unrelated API/daemon work unless that
termination is explicitly the combined role's contract. A startup warm-up task that completes while
the API stays alive is a different lifecycle from a terminating job.

| Event | Expected evidence |
| --- | --- |
| Finite command succeeds | Work completed, cleanup awaited, process exits successfully without lingering web listeners |
| Finite command fails | Explicit failure and nonzero exit; deployment hook/job cannot report success |
| Long-running worker completes unexpectedly | Defined supervisor failure/restart policy, not a healthy idle container |
| Host receives shutdown | Children cancel, ownership/streams/scopes drain and process exits within its grace period |
| One worker faults in a combined role | Configured process failure or documented contained recovery; no orphaned sibling tasks |

## Replica Ownership

Classify each worker as:

- Per-replica work, such as local housekeeping.
- Distributed consumers with partition/queue ownership.
- Leader-only work needing one current owner.
- A finite job coordinated by the deployment/job runner.

One configured feature, one registered singleton or one Kubernetes replica is not a general
distributed exactly-once guarantee. Use the leadership skill for lease acquisition/loss, fencing
where needed, cancellation and failover. Keep followers' unrelated serving/probes available.
Inspect every mutation path: merely registering a leadership runner does not gate any worker.

## Health and Deployment Contracts

- **Liveness:** can the process continue functioning? Do not fail it solely for an unavailable
  optional dependency or leadership contention, causing a restart storm.
- **Readiness:** can this selected role perform its required responsibility now? An idle queue or
  standby replica can be healthy; a dead required loop is not made healthy by an HTTP listener.
- **Startup:** have required initialization and dependencies completed within the allowed budget?
  Use a startup gate/probe where appropriate rather than relaxing all readiness checks.

Register only applicable checks and agree on degraded versus unhealthy outcomes. A worker-only role
may still expose a management/probe listener; it must not accidentally expose the application's
business API. A finite job usually relies on completion/exit status rather than a daemon probe.
Do not claim separate readiness/liveness behavior if the application only maps a single basic
health endpoint.

Keep image digest fixed across role deployments while validating role-specific command/arguments,
resources, secrets, service exposure, restart policy, termination grace and probe paths. Distinct
roles may scale independently; co-hosted roles share restarts and rollout. Follow Helm/GitOps
skills for concrete manifests rather than duplicating chart contracts here.

Official sources:
[Worker Services](https://learn.microsoft.com/en-us/dotnet/core/extensions/workers),
[scoped services in workers](https://learn.microsoft.com/en-us/dotnet/core/extensions/scoped-service),
[health checks](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks?view=aspnetcore-10.0),
[Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/).
