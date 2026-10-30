# Runtime Composition and Module Boundaries

## One Artifact, Multiple Runtime Purposes

Use one canonical Dockerfile/release artifact for the application's supported roles. Keep its
entrypoint stable; select the role through validated startup configuration or arguments.
An API-only instance, worker-only instance and combined instance can use the same digest while
receiving different resources, permissions, probes and enabled modules.

This is not a mandate to combine unrelated applications or use one giant dependency graph.
The tradeoff is a common release artifact/dependency footprint and, for co-hosted roles, shared
process resources, failure and rollout. Separate deployments can scale roles independently while
retaining one image. Extraction into another service requires a real ownership/scaling/release
boundary, not merely a new background loop.

Do not add another Dockerfile/image per feature to solve a registration bug. Conversely, do not
hide a genuinely incompatible native dependency or trust boundary behind a runtime flag; explain
the constraint and use an explicit design decision when the common artifact no longer fits.

## Two Supported Startup Shapes

| Shape | Appropriate use | Details to establish |
| --- | --- | --- |
| Validated feature set | Several independently enabled workers/modules can run singly or together | Known names, defaults, normalization, dependency combinations, web exposure and supervised workers |
| Explicit finite mode plus normal server composition | A migration/import/admin command shares the normal artifact but must terminate | Argument precedence, required dependencies, no incidental server startup, failure/exit semantics |

Both are legitimate. A modular application need not implement a name-based background dispatcher
just because another application does. Configuration booleans and explicit composition methods can
be sufficient for a small fixed set; avoid a second interchangeable role/feature vocabulary without
a consumer requirement.

For a validated feature set, an established implementation may trim comma-separated names,
deduplicate case-insensitively and reject unknown values. Verify rather than assume those exact
semantics. Decide whether an empty set is invalid or intentionally means a supported web-only role;
do not let the parser and dispatcher disagree.

Selection is an immutable startup snapshot unless the application deliberately implements atomic
in-process reconfiguration. A dynamic business flag is not permission to start/stop DI registrations,
hosted services or middleware after construction.

## Composition Root and Shared Infrastructure

- Give each capability a cohesive registration method and owned implementation. Keep the top-level
  host shallow; pass a small feature-derived state object where needed to coordinate run-once
  shared registration, not a growing tuple of unrelated flags.
- Compute prerequisites from the supported combinations. Shared messaging, health, serialization,
  persistence or routing foundations may be needed by several roles; register them once.
- “Feature disabled” can still require a lightweight dependency for another active module. Separate
  registration of a contract/sink from starting its network connection or full worker.
- Inspect assembly scanning: scanning every assembly can instantiate or register inactive workers,
  controllers or options validators despite a feature method returning early.
- Validate only genuinely required role-specific external configuration. A disabled module should
  not force unrelated credentials, device access or a database connection through eager startup.
  Validate all selected modules; do not silently ignore missing prerequisites.
- Do not equate an in-memory channel, singleton or callback with cross-process delivery. If
  separating producer and consumer roles, trace the actual transport and durable ownership.

## Controller, Endpoint and Documentation Gates

Choose the existing mechanism that matches the application:

- **Separate module assemblies:** add only selected controller application parts, verifying default
  discovery does not already include disabled ones.
- **Single/shared assembly:** filter controller discovery with the existing feature provider;
  conditional DI registration alone cannot hide compiled controllers.
- **Minimal APIs, hubs, MCP and frontend:** map each surface deliberately. MVC discovery filtering
  does not automatically gate any of these independent surfaces.

In the shared `FeatureController`/`AddFeatureGatedControllers` pattern, verify the consumer's
version: the inspected provider uses **OR/overlap** across a controller's declared features, and
unmarked controllers remain discoverable. An endpoint that needs two modules cannot express an
AND prerequisite by listing two names on an OR-gated attribute. Register its real dependencies
for every exposing selection, or enforce the required combination explicitly.

Discovery filtering should agree with routing and API Explorer/OpenAPI. A disabled surface should
not advertise a route that fails at activation. Merely returning 403, hiding a UI link, or removing
an OpenAPI entry is not proof the route is disabled. Keep authorization in place for enabled
surfaces; role gating is not a replacement for it.

## Layered Boundaries and Dependency Direction

### Classify What Is Actually Separated

Logical presentation, application, domain and infrastructure layers can coexist inside one process
and one release image. A physical tier is an independently running boundary, not a namespace or
project. Do not describe a controller/service/store call chain as a three-tier deployment without
evidence of separate processes. Modular-monolith and layered designs are compatible.

Ports/adapters describes a different axis: the application owns the contract it needs, while an
external-system adapter implements it. A provider interface alone does not prove inward dependency
direction. Verify who defines the contract, which assemblies reference which, and where concrete
implementations are selected.

### Trace and Improve the Boundary

1. Identify the capability owner and the public operation it exposes. Trace caller to service,
   domain behavior and persistence/integration, including background and administrative paths.
2. Inspect actual project/package references, public method signatures, constructors and direct
   namespace/type usage. An infrastructure entity returned by an application API can leak EF or
   provider dependencies even when project names look clean.
3. Record allowed dependencies at the application's current granularity. A typical direction is
   transport to application, application to domain/contracts, and adapters to the contracts they
   implement; the composition root knows the concrete registrations. Do not mandate four projects
   per module or relocate existing working boundaries merely to match these labels.
4. For a cross-module operation, call the owning module's deliberate contract instead of reaching
   into its store, context or mutable internal objects. Keep validation/authorization and invariant
   ownership with the application boundary; a shared database does not imply shared write ownership.
5. Choose a synchronous in-process call when the caller needs an immediate outcome. Introduce
   events only when independent reactions or asynchronous delivery are required, and define
   ordering, delivery and failure semantics. An in-process event does not provide durable delivery
   across independently configured roles.
6. Remove cycles at the real responsibility boundary, not by hiding dependencies behind
   `IServiceProvider`, reflection, a global event bus or an indiscriminate shared-contracts project.
   Keep application policy in its module; extract only contracts with real consumers.
7. Prefer a local extraction of a cohesive service/contract when sufficient. Moving a capability
   across assemblies can alter DI discovery, controller parts, serialization and packaging;
   validate those affected surfaces using the main workflow.

### Enforce Only What Can Be Proven

Use existing architecture tests/analyzers when present; do not add a test framework by default.
For multiple assemblies, assert allowed project and assembly references and inspect public API
dependency leakage. For a single assembly, use namespace/type-level checks or targeted review,
because project-reference tests cannot detect forbidden internal calls. Check runtime scanning
and dynamic resolution separately.

The [layered module example](../examples/layered-module-boundaries.md) supplies a concrete allowed
reference graph and negative cases. Keep these rules scoped to the application, not a fleet-wide
requirement for identical project layouts.

Check data ownership as well as dependency direction:

- Modules expose deliberate contracts rather than another module's internals.
- Public contracts do not force server/execution dependencies into frontend clients.
- Modules do not silently mutate each other's private persistence state.
- Shared utilities remain generic; application-specific policy stays local.
- New abstractions are justified by real reuse, tests or a public extension boundary.
- Runtime activation is distinguished from compile-time inclusion and security isolation.

Use architecture records for consequential boundary changes; do not manufacture an ADR for every
small registration edit.

Official sources:
[dependency injection](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection),
[application parts](https://learn.microsoft.com/en-us/aspnet/core/mvc/advanced/app-parts?view=aspnetcore-10.0),
[Generic Host](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host).
