---
name: dotnet-apphost
description: 'Design, align, refactor, audit or troubleshoot .NET application bootstrapping and AppHost composition: thin Program entry points, configuration/logging/telemetry ordering, feature and role registration, finite migration and ingestion modes, interactive consoles, Web API/MCP/gRPC wiring, middleware and endpoint order, health, shutdown, process results and host tests. Use for AppHost.cs, Program.cs and cross-application bootstrap consistency.'
argument-hint: '[design|apply|audit|diagnose] [application or host concern]'
user-invocable: true
---

# .NET Application Host

Keep application startup readable, testable and application-owned. Align composition roots without
turning intentional differences into one hidden framework.

## Authorities

- Follow the shared [.NET](../../instructions/dotnet.instructions.md),
  [C#](../../instructions/dotnet.csharp.instructions.md),
  [configuration](../../instructions/dotnet.configuration.instructions.md), and
  [testing](../../instructions/dotnet.testing.instructions.md) instructions.
- Use [dependency injection](../dotnet-dependency-injection/SKILL.md) for lifetimes, aliases,
  factories, scopes and disposal.
- Use [modular monolith](../patterns-modular-monolith/SKILL.md) for feature-selected modules,
  runtime roles, worker/API composition and replica ownership.
- Use [Web API](../dotnet-webapi/SKILL.md), [gRPC](../dotnet-grpc/SKILL.md),
  [MCP](../dotnet-mcp/SKILL.md), [CLI](../dotnet-cli/SKILL.md), and
  [background pipelines](../dotnet-background-pipelines/SKILL.md) for their protocol or lifecycle
  details. This skill owns how those capabilities are composed into the application host.
- Use [EF Core](../dotnet-efcore/SKILL.md) for schema migration correctness and
  [Helm](../kubernetes-helm/SKILL.md) for the external migration Job contract.
- Load the [alignment reference](./references/apphost-alignment.md) for the comparison matrix,
  preferred file roles and acceptance checks.
- Use the [process outcome example](./examples/process-outcome.md) for Kubernetes daemon and finite
  job exit semantics.

## Modes

| Mode | Outcome |
| --- | --- |
| `design` | Propose bounded AppHost/file-role alignment without editing |
| `apply` | Refactor the requested host while preserving its runtime contract |
| `audit` | Report the effective bootstrap, differences, risks and missing coverage |
| `diagnose` | Trace one startup, DI, middleware, endpoint, health, shutdown or exit failure |

Ask when the mode is ambiguous and the difference would change whether files are edited.

## Workflow

### 1. Establish Current Ownership

1. Read repository instructions, current branch and worktree before editing. Treat current workspace
   branches as authoritative when the user says parallel work is in progress.
2. Do not edit a dirty repository whose changes belong to another session unless the requested file
   and intended integration are unambiguous. Never revert or normalize unrelated changes.
3. Inventory every executable entry point and the project or assembly containing its composition
   root. Distinguish ASP.NET Core servers, Generic Host daemons, interactive consoles and finite
   administrative modes. Test projects with `OutputType=Exe` are not application entry points
   unless they own an application `Program` or host.
4. Read host tests, deployment invocation, Docker entrypoint, feature/role configuration and shared
   hosting package versions before proposing alignment.

### 2. Trace the Effective Lifecycle

Trace executed code in order:

1. argument parsing or special modes;
2. removal or normalization of host-only arguments before configuration binding;
3. bootstrap logging;
4. builder creation;
5. configuration providers and secret-store augmentation;
6. root options binding and validation;
7. logging;
8. infrastructure and dependency registration;
9. observability;
10. feature/role validation and registration;
11. Web API, MCP, gRPC and other transport registration;
12. host options and shutdown;
13. build;
14. middleware;
15. endpoint mapping;
16. run or finite operation;
17. cancellation, failure, logging flush, disposal and process result.

Record where each step lives and the state it passes to later phases. Do not infer behavior from
filename symmetry.

### 3. Separate Alignment From Behavior Change

Classify each proposed change:

- file-only movement;
- naming or signature alignment;
- lifecycle-order change;
- service-registration change;
- middleware-order change;
- endpoint-contract change;
- configuration or role-selection change;
- failure, shutdown or exit-code change.

File-only alignment should preserve behavior. Any other category requires explicit evidence,
focused tests and user confirmation when it changes an external or operational contract.

### 4. Apply the Smallest Useful Shape

Prefer:

- a tiny `Program.cs` that delegates to an application-owned `AppHost`;
- one visible orchestration method;
- focused partial files when the host is large;
- an `AppHost.<Mode>.cs` partial when a migration, ingestion, benchmark or other mode has a distinct
  lifecycle substantial enough to obscure the main orchestration;
- feature methods that return early when disabled;
- explicit transport and endpoint wiring;
- shared primitives from existing packages;
- typed local state when several later phases need the same derived switches.

Avoid:

- `Startup`/`UseStartup`;
- inheritance-based application hosts;
- generic module frameworks introduced only to reduce line count;
- one `AddEverything` call hiding supported roles and surfaces;
- assembly scanning when explicit registration is practical;
- `BuildServiceProvider` during registration;
- static mutable startup state;
- moving domain policy into a shared hosting package;
- making applications acquire unused controllers, transports or middleware for visual uniformity.

### 5. Decide What Is Actually Shared

Before extracting code, require at least two real consumers with matching semantics. Compare:

- inputs and defaults;
- configuration timing and validation;
- service lifetimes;
- middleware and endpoint order;
- failure and cancellation behavior;
- health meaning;
- observable logs, metrics and traces;
- test seams.

Keep application-owned composition local when only the syntax matches. Shared hosting packages
should expose primitives, not know application feature names, domain services or endpoint inventories.

### 6. Update Every Surface

When applying a change, update together:

- entry points and AppHost partials;
- project references and global usings;
- configuration and options;
- feature/role constants and validation;
- controller discovery, API documentation and endpoint mapping;
- health registrations and probe routes;
- host/startup tests;
- application README or architecture documentation;
- Debug project references and Release package references where affected.

Preserve `WebApplicationFactory` entry-point markers and test accessibility.

## Validation

Ask before builds or tests. Start with static compilation/editor diagnostics and the smallest host
tests covering the change. When authorized, validate:

- missing and invalid configuration fails safely;
- every supported role resolves its DI graph;
- disabled features expose no endpoints or workers;
- middleware and endpoint inventory match the prior contract;
- liveness and readiness retain their meanings;
- finite modes do not start unrelated services;
- command-line mode overrides have defined precedence and do not leak host-only arguments into
  ordinary configuration;
- worker-only roles expose only their intended operational surface;
- interactive consoles translate Ctrl+C into cooperative cancellation and dispose their host;
- Debug-only host modes fail clearly in Release rather than silently changing behavior;
- shared infrastructure required by several features is registered once;
- every thin entry point passes the intended entry assembly for user-secrets/configuration behavior;
- cancellation and shutdown are bounded;
- unexpected faults remain failures;
- fatal background-service faults survive graceful `StopHost` shutdown as a nonzero process result;
- logging and telemetry initialize once and flush;
- the actual process or test host starts for each affected composition.

Build the complete Debug solution when it uses adjacent source references. Validate the Release
solution after the required package versions exist; never predict unpublished versions.

## Reporting

Report:

- entry points and supported host modes;
- lifecycle before and after;
- intentional differences retained;
- files and contracts changed;
- shared primitives reused or deliberately not extracted;
- validation run and not run;
- remaining operational risks.

Do not commit, push, publish or deploy unless separately authorized.

## Maintaining This Skill

- Fold verified cross-application lessons into this skill or its alignment reference.
- Keep protocol-specific detail in the linked skills.
- Add an acceptance case when a new host mode exposes a reusable lifecycle distinction.
- Do not add a second AppHost skill until repeated use demonstrates a genuinely separate workflow.
