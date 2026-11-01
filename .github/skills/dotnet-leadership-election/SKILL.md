---
name: dotnet-leadership-election
description: 'Create, audit or troubleshoot Redlock-backed leadership election through CasCap.Common.Caching. Use for leader-only background workers, distributed singleton ownership, lease renewal or loss, contention, failover, replica readiness, local Redis development and leadership telemetry.'
argument-hint: 'mode={audit|apply|diagnose} [scope=worker|application|workspace]'
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

## Workflow

Each step states the decisive rules; open the linked reference for the full procedure before
editing that surface.

### 1. Establish the Ownership Contract

- Inventory every lock factory, lease, Redlock configuration/profile, leadership state and
  leader-gated worker, including tests, deployment values, health checks, metrics and docs.
- Classify the protected work (singleton, shared-lifetime loop set, independent partitions or a
  short critical section) and gate only side effects that require ownership.
- Define resource identity, timing profile, contention, lease-loss, shutdown and failover policy
  before implementing; reuse shared lifecycle helpers rather than adding another election loop.
- Detail: [ownership contract](./references/ownership-contract.md).

### 2. Wire the Shared Caching Contract

- Use `AddCasCapCaching(...)`, `IDistributedLockFactory`, `IOptions<RedlockConfig>` and the
  `RedlockProfiles.LeaderElection` profile; never reuse cache-miss timings for a perpetual worker.
- Keep `CachingConfig.Redlock` the single configuration source; add only scoped leadership
  lifecycle settings and never a second factory, connection or binding section.
- Require remote Redis and enabled locking for an elected worker and fail explicitly otherwise;
  treat database, prefix, resource-dimension or key-format changes as an ownership migration.
- Detail, timings, the provisional `ILeadershipRunner` contract and the integration procedure:
  [shared caching contract](./references/shared-caching-contract.md).

### 3. Bind Work to a Lease Lifetime

- Follow **contend -> acquire -> start -> active -> stop -> release -> contend**; contention is a
  normal standby outcome, never permission to run leader-only work.
- Hold the lease for the whole protected lifetime, pass a linked ownership token everywhere, await
  child tasks, cancel on loss and await cleanup before reacquiring a fresh lease.
- Redlock is coordination, not exactly-once execution or fencing; protect stale-owner writes
  downstream where they cannot be tolerated.
- Detail, coordinated schedules, delivery and RedLock.net state semantics:
  [lease lifecycle](./references/lease-lifecycle.md).

### 4. Expose Coherent State and Health

- Keep one thread-safe, authoritative snapshot of election phase, run identity and worker progress
  shared by metrics, health and command gateways.
- Separate lease ownership from business readiness and process liveness; a healthy standby is not a
  failed process.
- Bind every user of a leader-owned connection, callback and command path to the ownership
  lifetime; fail closed before ownership is initialized and park terminal external failures.
- Detail: [state, health and external connections](./references/state-health-and-connections.md).

### 5. Preserve Deployment and Local-Development Semantics

- Replicas must share the intended Redis backend, database and effective election key; never place
  leases on a failover-managed primary.
- Make local/mock/replay bypass explicit and restricted; align shutdown and termination budgets.
- Detail: [deployment and validation](./references/deployment-and-validation.md#deployment-and-local-development).

### 6. Validate the Actual Contract

- Build the affected projects and ask before executing tests; prefer deterministic lease fakes,
  with approved shared-Redis integration tests for contention and renewal.
- Cover the scenario matrix, report gaps honestly and never delete lock keys to force leadership.
- Detail: [deployment and validation](./references/deployment-and-validation.md#validation-and-diagnosis).

## Maintaining This Skill

- Recheck shared registration, configuration/profile APIs and package availability when
  `CasCap.Common.Caching` changes; keep published-package behavior separate from checkout behavior
  in the [shared caching contract](./references/shared-caching-contract.md).
- Recheck RedLock.net overloads, renewal, state/loss signals, cancellation and disposal semantics
  when its version changes, and update the [lease lifecycle](./references/lease-lifecycle.md).
- Fold newly verified reusable lifecycle, state, gateway and validation patterns into the owning
  reference without importing private application details or promoting existing implementation
  gaps; keep the SKILL.md step summaries in step with them.
- Revisit readiness, shutdown budgets and topology assumptions when host, chart or Redis
  architecture changes.
- Keep the owned-worker example aligned with the verified runner contract; compile against the
  real implementation and distinguish consumer fake tests from Redis/renewal evidence.
