# One Image, Four Runtime Profiles

A synthetic catalog application publishes one immutable release image from its canonical
Dockerfile. It can expose a catalog API, process inventory messages, combine the two, or run a
finite schema migration. This example defines configuration and observable behavior; it is not
a drop-in implementation or permission to start workers or alter a database.

## Feature Selection

Suppose this application's existing startup contract binds `Example:Features:Enabled` as a
comma-separated set. The example deliberately chooses trim, case-insensitive deduplication,
unknown-name rejection and no empty daemon selection.

Daemon profiles pass these runtime environment overrides:

```text
API:       Example__Features__Enabled=CatalogApi
Worker:    Example__Features__Enabled=InventoryWorker
Combined:  Example__Features__Enabled=CatalogApi,InventoryWorker
```

These are synthetic keys, not the shared hosting library's fixed configuration path. Use the
actual options binding of the target application; do not copy this key into another application
without wiring it. Role configuration stays external to the image.

| Profile | Active modules | Web exposure | Lifetime/ownership |
| --- | --- | --- | --- |
| API | Catalog queries and API contracts | Catalog routes plus management/probes | Daemon; scales according to HTTP load |
| Worker | Inventory consumer and its store/transport | Management/probes only | Daemon; queue/partition ownership, not implied leadership |
| Combined | Both; shared store/transport registered once where needed | Same catalog routes as API profile | Daemon; co-hosted resource/failure budget |
| Migration | Only migration dependencies | No server startup | Explicit finite command using the same image; external rollout step |

The migration profile uses an explicit command-line switch such as `--migrate`, parsed before
normal server startup. Its command must not require a fake worker feature simply to satisfy a
daemon dispatcher. Define precedence explicitly if both the switch and daemon settings are supplied.

## Conditional Registration

The composition performs these concrete steps:

1. Determine finite mode versus daemon mode.
2. In daemon mode, bind and validate feature names and prerequisites.
3. Add the shared store once when either active capability requires it.
4. Add catalog query/API services only for `CatalogApi`.
5. Add and launch the inventory consumer only for `InventoryWorker`.
6. Filter MVC discovery and map independent non-MVC surfaces for the selected capabilities.
7. Add role-appropriate health checks and run the host.

Use existing feature/hosting helpers; these steps are not a request to implement a second registry
or dispatcher. Do not register all hosted services and hope they never execute when disabled.

## Controller Gating Truth Table

When using a verified OR/overlap-based controller provider:

| Controller declaration | API only | Worker only | Combined |
| --- | --- | --- | --- |
| Requires `CatalogApi` | Present | Absent | Present |
| Lists `CatalogApi` and `InventoryWorker` with OR semantics | Present | Present | Present |
| Unmarked | Present | Present | Present |

The second declaration does **not** mean both modules are required. If its constructor needs both
sets of dependencies, the single-feature profiles would be broken. Choose an explicit combined
gate/dependency design instead of misusing the OR list. Unmarked controllers are safe only when
their dependencies and intended availability really are common.

Test actual routing and OpenAPI, not just the selected names. Minimal APIs, hubs, frontend and MCP
mapping need their own gates; a controller feature provider cannot control them.

## Worker and Job Failure Cases

| Scenario | Required observation |
| --- | --- |
| `CatalogApi, catalogapi` | One effective feature selection; no duplicate shared registration |
| Unknown `InventoryWorkre` | Explicit startup validation failure, not an idle “healthy” container |
| Disabled inventory consumer | No consumer launch and no requirement for its unrelated credentials |
| Duplicate matching worker registrations | Detected by composition tests; set deduplication alone does not prevent two launches |
| Inventory consumer throws | Defined supervisor policy, observed sibling cleanup and process outcome |
| Healthy consumer has no messages | Healthy idle state, not a liveness failure for zero throughput |
| Migration finishes | Successful finite exit, no API listener; ordinary serving deployments are untouched |
| Migration fails | Nonzero exit and rollout blocked; no success-shaped fallback |
| Shutdown during combined operation | Both active lifecycles cancel and drain within the grace period |

Do not append a terminating migration worker to the combined profile casually: calling
`StopApplication` after migration would also stop the API and inventory consumer.

## What to Verify

- The image digest is identical for every profile; selection changes configuration/arguments only.
- Each profile validates DI without inactive-module prerequisites.
- Route and OpenAPI presence match the truth table and supported prerequisites.
- The consumer starts once per intended owner and does not assume cross-process in-memory delivery.
- Finite and daemon completion/fault/cancellation have the specified process outcomes.

These are acceptance cases, not executed results. Use existing host/route tests and isolated
fake dependencies before any authorized container or live workload validation.
