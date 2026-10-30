---
name: patterns-modular-monolith
description: 'Design, implement, audit or troubleshoot .NET modular monoliths with one Dockerfile and release image serving multiple configured roles. Use for layered module boundaries, dependency direction, feature-selected modules, workers running singly or together, composition roots, controller/OpenAPI gating, run-once jobs, worker lifecycle, replica ownership, and role-aware health and deployment contracts.'
argument-hint: '[design|apply|audit|diagnose] [module or runtime role]'
user-invocable: true
---

# Modular Monolith

Build one application artifact and compose its runtime responsibilities deliberately. The same
release image can serve an API, run selected workers, combine compatible responsibilities, or
execute a finite administrative role. A new purpose does not automatically need another project
entrypoint, Dockerfile, image or microservice.

## Scope and Authorities

| Concern | Authority |
| --- | --- |
| Feature selection, module composition, worker/API boundaries and role contracts | This skill and [composition reference](./references/composition.md) |
| Integration contracts, provider substitution and adapter semantics | [Ports and adapters](../patterns-ports-and-adapters/SKILL.md) |
| Service lifetimes, factories, aliases and scoped operations | [.NET dependency injection](../dotnet-dependency-injection/SKILL.md) |
| Bounded queues, backpressure, delivery and drain protocols | [.NET background pipelines](../dotnet-background-pipelines/SKILL.md) |
| Finite-command dispatch, help/version and process exit status | [.NET CLI](../dotnet-cli/SKILL.md) |
| Worker lifetime, completion, failure, readiness and role validation | [Lifecycle and operations](./references/lifecycle-and-operations.md) |
| C# wiring, async work and shutdown | [C# instructions](../../instructions/dotnet.csharp.instructions.md) |
| Startup configuration, secrets and reload policy | [Configuration instructions](../../instructions/dotnet.configuration.instructions.md) |
| Dockerfile/profile/platform authoring | [Container images](../containers-images/SKILL.md) |
| Shared build and deployment entrypoints | [Container workflows](../containers-workflows/SKILL.md) |
| Workload/chart rendering and GitOps ownership | [Helm charts](../kubernetes-helm/SKILL.md), [GitOps structure](../gitops-repository-structure/SKILL.md) |
| Leader-only worker ownership | [Leadership election](../dotnet-leadership-election/SKILL.md) |
| Persistence and schema rollout | [EF Core data access](../dotnet-efcore/SKILL.md) |
| Architecture decisions and frontend/API contracts | [ADR authoring](../docs-adr/SKILL.md), [Blazor frontend](../dotnet-blazor/SKILL.md), [.NET Web API](../dotnet-webapi/SKILL.md) |

The [one-image role example](./examples/role-profiles.md) shows an API, worker, combined role and
finite job with concrete startup selections and acceptance cases. It is synthetic guidance, not
a production manifest or a new hosting framework.
The [shared-hosting wiring example](./examples/shared-hosting-wiring.md) shows verified DI and
controller APIs with explicit package/fixture limitations.
The [layered module example](./examples/layered-module-boundaries.md) shows project references,
application-owned ports, cross-module calls and boundary checks without adding deployment tiers.

## Modes and Boundaries

- `design`: inspect current architecture and propose module/role boundaries without edits.
- `apply`: implement the requested module or role, wire relevant surfaces and document its contract.
- `audit`: report source-backed composition, lifecycle and isolation findings without changes.
- `diagnose`: trace one missing endpoint, dependency failure, duplicate worker, unexpected shutdown
  or readiness problem from runtime selection through its owning implementation.
- Scope to the requested application. Preserve its current module granularity and hosting
  mechanism unless changing them is explicitly in scope. A single assembly and multiple module
  assemblies are both valid; a directory name alone does not establish an enforced boundary.
- Do not deploy, run live workers/jobs, apply schema changes, stop replicas or change configuration
  in a shared environment without explicit authorization. Ask before builds and tests.
- Extract reusable lessons, not private feature names, topology or configuration. Verify the
  consumer's pinned shared package exposes the APIs being proposed; a neighboring checkout is
  not proof that a released package contains them.

## Workflow

### 1. Trace the Existing Host

1. Read repository notes, relevant ADRs and the worktree. Trace the actual entrypoint, composition
   root, configuration binding/validation, feature parsing, module registration, hosted dispatch,
   endpoint mapping and shutdown. Separate documentation intent from executed code.
2. Trace the canonical Dockerfile through publish and entrypoint. Identify the artifact that each
   runtime role consumes; distinguish Debug stages or platform variants from separate purpose-built
   products. Check role selection is runtime configuration/arguments, not a hidden rebuild switch.
3. Inventory shared services, assembly scanning, controllers, minimal APIs, hubs, frontend/MCP
   surfaces, worker implementations, finite jobs and health registrations. Find what actually
   enforces each gate; registering a service or naming a feature does not gate its endpoints.
4. Follow the existing shared hosting helpers before adding a custom dispatcher or feature flag
   abstraction. Record their empty/unknown selection, overlap, duplicates, completion, cancellation
   and exception semantics; do not assume every application uses the same mechanism.
5. Map compile-time references and actual cross-module calls using the composition reference's
   layered-boundary procedure. Distinguish logical layers, physical tiers and ports/adapters;
   do not infer architectural enforcement from folders or interface names.

### 2. Define the Module and Runtime Role Matrix

For every affected role, record:

| Selection | Required modules/dependencies | Exposed surfaces | Work and ownership | Lifecycle | Health and resources |
| --- | --- | --- | --- | --- | --- |

Separate three axes:

- **Module:** a capability with owned implementation/contracts and declared dependencies.
- **Role:** a supported composition of capabilities in one process using the shared image.
- **Replica ownership:** every replica, a queue/partition consumer, or a distributed singleton.

Enabling one worker in one process does not guarantee one execution across replicas. Different
processes sharing an image do not share in-memory channels, caches or locks.

Confirm ambiguous choices: default/empty selection, supported combinations, implicit prerequisites,
run-once versus daemon behavior and required readiness. Avoid inventing a fleet-wide role registry
when an application's existing validated feature set or small startup-mode branch is sufficient.

### 3. Compose Without Accidental Coupling

1. Keep `Program` wiring-only and split registration into focused module/feature methods. Register
   only active execution paths and needed shared prerequisites; deduplicate cross-cutting
   infrastructure. Keep module business logic out of the composition root.
2. Validate the effective startup selection and its dependencies before launching work. Normalize
   only according to the established contract, reject unknown/unsupported selections explicitly,
   and avoid permissive defaults that turn a typo into a role doing nothing or everything.
3. Wire service registration, controller discovery, OpenAPI and endpoint mapping consistently.
   Single-assembly controller discovery can expose a feature controller whose dependencies were
   never registered; hiding the menu or documentation is not sufficient.
4. Define dependencies at module boundaries and reuse contracts/services rather than reaching into
   another module's private implementation or database mappings. Share process infrastructure, not
   a global service locator. Avoid interfaces/events or a plugin framework for speculative reuse.
5. Configure each role with only its required external access and capabilities. A common artifact
   may contain inactive assemblies; runtime gates are not a hard security or dependency-isolation
   boundary. Keep browser-delivered code and credentials separate.

### 4. Wire Lifecycle and Operations

Apply the lifecycle reference before combining work:

- Preserve concurrent worker supervision, propagated cancellation and awaited cleanup.
- Decide what a finite job's success/failure means for the host and process exit status.
- Do not let a run-once feature stop unrelated API/worker roles accidentally.
- Keep role-specific readiness separate from process liveness and leadership contention.
- Use the existing distributed ownership helper only for work that actually needs singleton
  ownership; leadership must not prevent healthy standby HTTP/probe service.
- Keep schema changes in a dedicated external migration role/step, ordered before normal rollout,
  not an unconditionally started worker in every replica.

Reuse the existing image/Dockerfile and deployment tooling. Role-specific configuration, resources,
probes, commands and workload type may differ without a different image. Do not publish/deploy
anything merely to demonstrate this structure.

### 5. Validate the Supported Compositions

With approval, run the smallest checks proving the affected role contract:

1. Parse and validate valid, duplicate, empty, unknown and incompatible selections.
2. Build a validated service provider for each supported affected composition, including disabled
   modules and optional infrastructure. Detect dependencies resolved only by constructors,
   middleware, scanning or static initializers.
3. Verify actual route/API Explorer/OpenAPI presence and absence, not only attribute declarations.
   Disabled feature routes should be unavailable without dependency-activation failures.
4. Verify exactly one launch per intended implementation, supported combined startup, finite
   completion, faults, host cancellation, cleanup and actual process exit code.
5. Confirm health checks use the role's required dependencies and lifecycle. Test healthy idle
   workers and standby leadership separately from stuck/unavailable required work.
6. If container validation is authorized, verify the same immutable image digest in each role;
   check startup/progress/shutdown as well as health. Use fake external dependencies or isolated
   fixtures unless live access is separately approved.
7. Verify affected dependency rules, including transitive package leakage and forbidden internal
   access. Project/assembly checks prove only their level of enforcement; a single assembly also
   needs symbol/namespace checks or explicit review of cross-module calls.

Report implementation, selected/supported roles, boundary enforcement, exact validation and
unverified live behavior. “One image builds” is not proof that all role combinations work.
Record intentionally deferred architectural work where its owner will find it.

## Maintaining This Skill

- Reverify shared hosting APIs, package availability, feature/controller gating and dispatch
  semantics when the hosting library changes; keep observed behavior distinct from desired policy.
- Refresh lifecycle guidance when .NET hosting, exception/exit handling, health probes or
  orchestrator job behavior changes. Preserve role-specific choices rather than universal defaults.
- Keep examples synchronized with the supported configuration contract and marked as illustrative
  until execution is verified; add a focused example only for a genuinely different useful pattern.
- Revisit dependency examples when module ownership, project references or packaging changes;
  keep intended dependency rules distinct from checks actually enforced by the repository.
- Move durable general lessons into the owning reference, while container, leadership, persistence,
  API and configuration procedures remain in their existing authorities.
