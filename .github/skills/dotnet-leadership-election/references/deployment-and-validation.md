# Deployment and Validation

Preserve deployment and local-development semantics, then validate and diagnose the actual contract.

## Deployment and Local Development

- Multiple replicas must share the intended Redis backend, database and effective election key.
  Merely increasing replicas or adding Redis to Compose does not prove mutual exclusion.
- Confirm the factory's actual Redis topology. Multiple connections to one backend are not
  independent Redlock voters; do not claim quorum fault tolerance from a single Redis container
  or an ordinary replicated Redis endpoint.
- Never place leases on a Sentinel-managed or otherwise failover-managed primary. Replication is
  asynchronous, so a failover can lose a just-granted lease and the promoted replica grants it to a
  second owner. Use an endpoint that never fails over; the `dotnet-redis` skill's topology
  reference covers placement and persistence for lock endpoints.
- Make local/mock/replay bypass explicit and restricted to work that cannot produce duplicate live
  side effects. Development mode alone is not a safe reason to bypass leadership.
- Use isolated development namespaces. Isolated Redis instances cannot validate cross-process
  contention; a shared development backend must not contend with another environment.
- Align host shutdown, connection teardown and container termination budgets. Review overlapping
  old/new pods during rollouts, lost-process expiry and restart/reacquisition behavior.
- Update every relevant options type, validator, appsettings layer, chart value, deployment
  override and operational example when changing the contract. Use the configuration-sync skill
  for an authorized private GitOps ConfigMap update rather than embedding deployment coordinates.

## Validation and Diagnosis

Build the affected projects and ask before executing tests. Prefer deterministic factory/lease fakes
for lifecycle tests, with approved shared-Redis integration tests for actual contention and renewal.

| Scenario | Evidence required |
| --- | --- |
| Same resource, multiple contenders | Only the acquired owner starts protected work; followers remain healthy standbys. |
| Independent partitions | Different intended resources can run concurrently; identical dimensions contend. |
| Cancellation during acquisition | Prompt exit without starting work or leaking a lease. |
| Startup or child-task failure | Observable failure, awaited cleanup, released state and bounded recovery. |
| Explicit provider quota rejection | Shared pacing, same-session bounded recovery, no password fallback, and operator-approved exhaustion/health policy. |
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
