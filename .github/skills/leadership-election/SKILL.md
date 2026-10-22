---
name: leadership-election
description: 'Create, audit or troubleshoot Redlock-backed leadership election through CasCap.Common.Caching. Use for leader-only background workers, distributed singleton ownership, lease renewal or loss, contention, failover, replica readiness, local Redis development and leadership telemetry.'
argument-hint: 'mode={audit|apply|diagnose} [scope=worker|application|workspace]'
user-invocable: true
---

# Leadership Election

Use a distributed lease to coordinate leader-only work across replicas. Keep ownership mechanics
reusable and application policy local. This skill describes an implementation and review procedure,
not a claim that every existing worker already implements lease-loss protection.

**Scope:** this skill is specific to solutions built on the `CasCap.Common.Caching` package and its
RedLock.net integration (`RedlockConfig`, `IDistributedLockFactory`, `IRedLock`). The lease
lifecycle, failover and validation guidance applies to any Redlock-style lease, but the type names,
configuration and helper calls are that library's.

The [Redis instructions](../../instructions/dotnet.redis.instructions.md) own key naming.
The [workflow instructions](../../instructions/workflow.instructions.md) own reuse, portability,
temporary duplication and deferred extraction. Follow the configuration, C# and testing instructions
when editing their respective surfaces.

## Modes and Boundaries

| Mode | Outcome |
| --- | --- |
| `audit` | Inventory election boundaries, shared contracts, configuration, safety gaps and validation evidence without edits. |
| `apply` | Implement the requested ownership behavior, wire every consumer and update related configuration, documentation and tests. |
| `diagnose` | Trace configuration, acquisition, lease state, worker progress and shutdown to explain contention or failover. |

- Do not deploy, change Redis state, stop replicas or run fault-injection experiments without
  authorization. Ask before running tests, including existing integration tests.
- Keep private application names, deployment details, resource keys and identifiers out of this
  central skill and any public reports. Use synthetic examples.
- Application Redlock election is distinct from Kubernetes controller leader election. Do not
  interchange their configuration, failure assumptions or APIs.

## 1. Establish the Ownership Contract

1. Find every `IDistributedLockFactory`, `IRedLock`, `CreateLockAsync`, `RedlockConfig`,
   `RedlockProfiles`, leadership state and leader-gated worker. Include registration, configuration,
   tests, local orchestration, deployment values, health checks, metrics and operational docs.
2. Classify the protected work:
   - One singleton worker, such as a scheduler, notifier or external connection monitor.
   - A set of related loops that must share one ownership lifetime.
   - Independently owned partitions, such as a tenant/account/workload combination.
   - Short critical sections or cache-miss suppression, which are not long-lived leadership.
3. Define exactly which side effects require ownership and which activities must run on every
   replica. Do not put HTTP serving, health endpoints or unrelated background work behind a global
   lease accidentally.
4. Define the resource identity, timing profile, contention policy, startup completion, lease-loss
   response, shutdown behavior and intended failover bound before changing implementation.
5. Search for reusable lifecycle/state helpers before adding another election loop. Separate
   generic acquisition, cancellation and state mechanics from business callbacks and partition
   identity. Use the shared caching library for reusable .NET mechanics; use a shared chart or
   workflow only for the deployment or automation contract it actually owns. Do not imply that an
   application-specific runtime helper already exists in the caching package.

## 2. Wire the Shared Caching Contract

The established shared integration uses:

| Surface | Role |
| --- | --- |
| `AddCasCapCaching(...)` | Registers caching and, when configured, the distributed-lock factory. |
| `IDistributedLockFactory` | Acquires a resource lease through `CreateLockAsync(...)`. |
| `IRedLock` | Exposes ownership state and asynchronous disposal. |
| `IOptions<RedlockConfig>` | Supplies lock configuration and named timing profiles. |
| `RedlockConfig.GetTimings(profileName)` | Resolves timings for the selected use case. |
| `RedlockProfiles.LeaderElection` | Selects leadership timings rather than short cache-miss timings. |
| `RedlockProfiles.CacheMiss` | Selects cache-miss protection, not a singleton-worker lifecycle. |

`RedlockConfig` is in `CasCap.Common.Models`. `GetTimings(...)` returns
`(TimeSpan expiry, TimeSpan wait, TimeSpan retry)`. The inspected shared configuration has these
defaults; verify the consumer's pinned version and overrides before relying on them:

| Timing source | Expiry | Acquisition wait | Retry interval |
| --- | --- | --- | --- |
| Root timings / missing named profile | 5 seconds | 5 seconds | 250 milliseconds |
| Built-in `LeaderElection` profile | 30 seconds | 60 seconds | 5 seconds |

Profiles are stored in `Dictionary<string, RedlockTimingProfile>`. An absent profile falls back to
root timings rather than failing; check that the intended election profile actually resolves.
`RedlockConfig` binds beneath the selected caching section's `Redlock` child, and
`CachingConfig.DistributedLockingEnabled` controls registration. Do not assume the root section
name when the caller overrides it.

### Configuration Ownership for New Abstractions

- Keep `CachingConfig.Redlock` as the single configuration source for both short-lived cache locks
  and leadership leases. A leadership runner consumes the existing `IOptions<RedlockConfig>` and
  registered `IDistributedLockFactory`; do not create a second Redis connection, factory, binding
  section or independently configured copy of expiry, wait, retry, database or key format.
- Preserve the existing distinction: `DistributedCacheService` currently calls `GetTimings()`
  for root cache-miss timings, while election uses `GetTimings(RedlockProfiles.LeaderElection)`.
  Do not move or rename the root configuration, make every lock use election timings, or route
  one-shot cache locking through a perpetual election/reacquisition loop.
- Add genuinely new lifecycle settings, such as loss-observation interval or cleanup budget, only
  where needed under the existing Redlock configuration, scoped to leadership behavior. Keep these
  separate from the Redis lease expiry and acquisition retry settings; do not duplicate equivalent
  knobs in application options or an unrelated feature-host configuration.
- Resolve the same configured Redlock options consistently through every `AddCasCapCaching`
  overload. Validate binding, default/profile selection and factory key/database configuration,
  and add regression coverage showing that changing leadership settings does not change
  cache-miss timings or behavior.

### Integration Procedure

1. Inspect the pinned `CasCap.Common.Caching` and RedLock.net versions and the actual overloads
   before writing calls. A local checkout may contain APIs not yet available in a published package.
   Do not add an independent RedLock factory or direct package reference just to duplicate the
   existing caching integration.
2. Verify the Redis connection and distributed-lock enablement. The shared registration requires
   remote Redis and enabled distributed locking; local-only caching is not cross-process election.
   Fail explicitly for an elected worker with missing prerequisites instead of silently running it
   without a lease.
3. Trace the configured Redis database and `RedisKeyFormat` through factory registration to the
   effective Redis key. Distinguish the logical resource passed to `CreateLockAsync` from the
   formatted storage key; avoid applying the prefix twice.
4. Resolve a dedicated election profile. Treat expiry, acquisition wait, retry interval and any
   outer-loop backoff as separate controls:
   - Expiry is the lease duration supplied to RedLock.net, not a fixed worker execution timeout.
   - Wait bounds an acquisition call; retry spaces attempts inside that call.
   - An outer contention loop can continue after the call fails to acquire.
   - RedLock.net manages renewal; verify the installed version's renewal and loss behavior.
     An application heartbeat does not renew a Redis lease.
5. Choose timings against expected pauses, Redis latency, startup, shutdown and takeover needs.
   Validate supported ranges and combinations. Do not promise takeover in exactly one expiry
   period or reuse short cache-miss timings for an indefinitely running worker.
6. Use deterministic, collision-free resource identities. All replicas of one partition must
   contend on the same effective key; safe independent partitions must use different keys.
   Isolate environments/installations where Redis is shared. Never add a pod ID or run ID to
   the election resource, and do not expose account identifiers through logs or metric labels.
7. Treat changes to database, prefix, resource dimensions or key format as an ownership migration:
   old and new replicas using different keys can both lead. Plan a controlled cutover rather than
   assuming a rolling configuration change preserves mutual exclusion.

## 3. Bind Work to a Lease Lifetime

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

In the inspected RedLock.net 2.3.2 API, `IRedLock` exposes `IsAcquired`, `Status`,
`InstanceSummary` and `ExtendCount`; status values include `Unlocked`, `Acquired`, `NoQuorum`,
`Conflicted` and `Expired`. No loss callback was identified in that API inspection. Verify
current semantics rather than inventing an event, treating an acquisition failure as a renewal
failure, or assuming `ExtendCount` proves that ownership is still valid now.

### Safety Beyond the Lease

Redlock is coordination, not exactly-once execution or a downstream fencing token. A paused owner
can resume after its lease has expired and another replica has acquired ownership. Redis topology,
failover, clock behavior and network partitions affect the guarantee.

For operations that cannot tolerate stale owners, use downstream-enforced fencing where supported,
plus idempotency or transactional checks as appropriate. A fencing token must be monotonically
ordered across owners and enforced by the resource accepting writes; a process-local generation,
GUID or heartbeat is not such a token. Gate side-effect entry points as well as the outer loop,
but do not present a check immediately before a write as atomic ownership enforcement.

## 4. Expose Coherent State and Health

- Keep a thread-safe, coherent snapshot of election phase, ownership-run identity, acquisition
  state, worker startup/progress and stop/failure state. Distinguish contending, starting, active,
  recovering, faulted and stopping where those phases exist.
- Treat election state and business readiness separately: a held lease does not prove that the
  external connection, warm-up or protected worker is ready.
- For a coordinated pipeline, include engine-running state and required-reader startup/liveness
  in the readiness projection. A startup latch is not a permanent readiness guarantee. On stop,
  cancel and await producers/readers before closing channels they still write to, and complete
  the rest of the pipeline's cleanup within the ownership lifetime.
- Distinguish local heartbeat/progress time from authoritative lease-renewal evidence. Do not name
  a timestamp "last renewed" if it only records an application's periodic observation.
- Observe acquisition latency, contention, ownership transitions, lease loss, worker failures and
  recovery. Keep labels bounded and free of resource/account identifiers and private content.
- Define active-worker readiness separately from process liveness and HTTP readiness. A healthy
  standby is not a failed process; do not make all followers unready for ordinary HTTP traffic or
  trigger restart storms merely because they do not own the lease.
- Ensure metrics, health endpoints, diagnostics and any leader-only command gateways use the same
  authoritative state rather than independent booleans that can disagree.

### External Connections and Callbacks

- Include every user of a leader-owned connection in the ownership lifetime, including outbound
  queue readers and command writers registered as separate background features. Cancel and join
  those users before disposing the connection; standbys must not consume commands they cannot send.
- Create fresh callback/reconnection buffers for each ownership run. Detach handlers and await
  asynchronous connection disposal on every exit, including partial startup. Fence late callbacks
  by their run and connection identity, not a mutable reference to the latest run.
- Replace untracked asynchronous event handlers with synchronous admission into an owned buffer and
  an awaited publisher. Propagate publisher/decoding failures through supervision, pass the run token
  to publication, and document buffering and non-replay semantics. SDK callbacks that cannot apply
  backpressure need an explicit overflow policy before a bounded buffer can safely replace them.
- Withdraw readiness on cancellation before waiting for cleanup. Serialize that transition with
  callback/health updates so a late update cannot reactivate an old run. An empty connection set
  does not establish readiness.
- Distinguish request-only disconnect APIs from awaited teardown. Retain producer and watchdog
  tasks and join them before reusing a connection or draining persistent buffers; starting a new
  subscription must not reactivate an old loop through a shared mutable subscribed flag.
- Keep reusable transport ownership separate from a lease session. Logout stops owned streams;
  final service disposal releases shared HTTP clients. Test resubscription with an uncancelled
  host token as well as shutdown, because host cancellation can conceal missing per-session stops.

## 5. Preserve Deployment and Local-Development Semantics

- Multiple replicas must share the intended Redis backend, database and effective election key.
  Merely increasing replicas or adding Redis to Compose does not prove mutual exclusion.
- Confirm the factory's actual Redis topology. Multiple connections to one backend are not
  independent Redlock voters; do not claim quorum fault tolerance from a single Redis container
  or an ordinary replicated Redis endpoint.
- Make local/mock/replay bypass explicit and restricted to work that cannot produce duplicate live
  side effects. Development mode alone is not a safe reason to bypass leadership.
- Use isolated development namespaces. Isolated Redis instances cannot validate cross-process
  contention; a shared development backend must not contend with another environment.
- Align host shutdown, connection teardown and container termination budgets. Review overlapping
  old/new pods during rollouts, lost-process expiry and restart/reacquisition behavior.
- Update every relevant options type, validator, appsettings layer, chart value, deployment
  override and operational example when changing the contract. Use the configuration-sync skill
  for an authorized private GitOps ConfigMap update rather than embedding deployment coordinates.

## 6. Validate the Actual Contract

Build the affected projects and ask before executing tests. Prefer deterministic factory/lease fakes
for lifecycle tests, with approved shared-Redis integration tests for actual contention and renewal.

| Scenario | Evidence required |
| --- | --- |
| Same resource, multiple contenders | Only the acquired owner starts protected work; followers remain healthy standbys. |
| Independent partitions | Different intended resources can run concurrently; identical dimensions contend. |
| Cancellation during acquisition | Prompt exit without starting work or leaking a lease. |
| Startup or child-task failure | Observable failure, awaited cleanup, released state and bounded recovery. |
| Work longer than expiry | Actual library renewal retains ownership, not merely a local heartbeat. |
| Renewal failure or lease loss | Active state is withdrawn, worker cancellation occurs and stale side effects are rejected where required. |
| Graceful handover | Protected tasks finish before release; a subsequent owner starts cleanly. |
| Uncooperative or paused owner | Explicit shutdown policy and downstream stale-owner protection; no exactly-once claim. |
| Reacquisition and late callbacks | Fresh run identity; old completion cannot overwrite new state. |
| Missing or disabled locking | Explicit configuration failure or documented safe mock mode, never silent live execution. |
| Key migration and rollout overlap | Old and new versions do not accidentally establish separate leadership domains. |

Measure detection, cancellation, cleanup and takeover against the agreed bounds, including configured
retry/backoff. Separate fake-based coverage from observed integration behavior and untested partition
assumptions. Report gaps honestly; do not infer failover safety from cache-lock tests or a
single-process success.

For diagnosis, trace prerequisites -> effective resource -> acquisition result -> current lease
state -> worker readiness/progress -> loss/stop cleanup. Do not delete lock keys to force leadership:
that can create concurrent owners and does not repair an uncooperative worker.

## Maintaining This Skill

- Recheck shared registration, configuration/profile APIs and package availability when
  `CasCap.Common.Caching` changes; keep published-package behavior separate from checkout behavior.
- Recheck RedLock.net overloads, renewal, state/loss signals, cancellation and disposal semantics
  when its version changes.
- Fold newly verified reusable lifecycle, state, gateway and validation patterns into the relevant
  section without importing private application details or promoting existing implementation gaps.
- Revisit readiness, shutdown budgets and topology assumptions when host, chart or Redis
  architecture changes.
