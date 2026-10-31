# AppHost Alignment Reference

Use this reference to compare composition roots without assuming identical applications need
identical hosts.

## Preferred File Roles

| File | Responsibility |
| --- | --- |
| `Program.cs` | Forward arguments and entry assembly; expose the test marker when required |
| `AppHost.cs` | Show lifecycle orchestration in execution order |
| `AppHost.Features.cs` | Register application features, workers and shared prerequisites |
| `AppHost.WebApi.cs` | Register controllers, API policies, serializers and documentation |
| `AppHost.Endpoints.cs` | Apply middleware and map endpoints in execution order |
| `AppHost.HostFeatures.cs` | Optional derived host switches shared by later phases |
| `AppHost.Grpc.cs` | Optional gRPC/Kestrel registration when substantial |
| `AppHost.Mcp.cs` | Optional MCP registration/mapping when substantial |
| `AppHost.<Mode>.cs` | Optional finite or specialized host mode with a distinct lifecycle |

Do not create every file in every application. A partial exists only when it makes a real concern
easier to inspect and test.

## Audit Matrix

| Concern | Evidence to record |
| --- | --- |
| Entry points | Executables, forwarded arguments, entry assembly, process result |
| Special modes | Migration, ingestion, finite jobs, interactive console, help/version |
| Argument precedence | Host-only parsing/removal, CLI override precedence, configuration arguments |
| Configuration | Providers, ordering, secret store, rebinding, validation |
| Logging | Bootstrap logger, provider replacement, runtime control, flush |
| Infrastructure | Time, cache, database, HTTP clients, shared singletons |
| Observability | Resource identity, meters, sources, exporters, sensitive-data policy |
| Features and roles | Selection, defaults, unknown values, prerequisites, workers |
| Web API | Controllers, discovery gating, auth, serialization, OpenAPI |
| MCP | Feature gate, tools/prompts, auth, Origin policy, route |
| gRPC | Services, ports, protocols, reflection, client/server roles |
| Middleware | Exact order and conditional branches |
| Endpoints | Routes per supported role; disabled-surface behavior |
| Health | Liveness, readiness, external dependencies, response shape |
| Shutdown | Timeout, cancellation, draining, disposal |
| Failure | Expected finite completion, unexpected faults, exit behavior |
| Tests | Startup compositions, endpoint inventory, missing dependencies |

## Alignment Decisions

For each difference, classify it:

| Classification | Action |
| --- | --- |
| Accidental drift | Align in the application |
| Application contract | Retain and document |
| Reusable primitive | Consider shared package extraction after two consumers |
| Protocol concern | Defer to the protocol-specific skill |
| Deployment concern | Preserve locally and coordinate with container/Helm guidance |
| Unproven abstraction | Keep local until evidence improves |

## Minimum Acceptance Cases

An AppHost refactor should normally prove:

1. The default supported role starts.
2. Every additional supported role or finite mode either starts or completes as designed.
3. Empty, unknown and incompatible role selections fail according to the existing contract.
4. Disabled controllers, MCP tools, gRPC services and workers remain unavailable.
5. Authentication and authorization remain attached to the same surfaces.
6. Middleware ordering preserves exception handling, routing, authentication, authorization and
   request logging behavior.
7. Liveness does not depend on failures it cannot repair; readiness reflects required dependencies.
8. Cancellation reaches workers and transports, shutdown remains bounded, and logging flushes.
9. No duplicate singleton, hosted service, database migration or event-stream owner is introduced.
10. Debug and Release dependency paths remain semantically equivalent.

## Scenario Catalogue

### Multiple Thin Entry Points

One shared AppHost can serve several entry assemblies or launch profiles. Verify that each entry:

- forwards the original arguments;
- passes its own entry assembly when configuration or user secrets depend on it;
- selects only its intended feature/role profile;
- preserves its process result and deployment invocation.

Do not require every entry point to expose a `Program` marker. Add one where an integration-test host
or another consumer needs it.

### Finite Migration or Administrative Mode

For Kubernetes-hosted EF Core applications, prefer one externally orchestrated migration Job using
the same immutable application image and a finite `--migrate` mode. Use an Argo CD PreSync hook or
equivalent release gate when schema must precede daemon rollout. Do not run migration from every
application replica or from one init container per replica.

The finite mode:

- parses and removes host-only arguments before ordinary configuration binding;
- overrides configured role selection only according to a documented precedence rule;
- rejects combination with daemon roles;
- registers only migration/administrative dependencies;
- builds a disposable host scope when DI is needed;
- does not start unrelated workers or transports;
- does not expose a Service or HTTP probes;
- completes with an explicit success/failure process result.

### Worker-Only or Ingestion Mode

A worker-only role may build an ASP.NET host for health/status endpoints while omitting the runtime
API. Verify that unrelated controllers, MCP tools, frontend assets and services are absent, not
merely unused.

### Interactive Generic Host

An interactive console can use `Host.CreateApplicationBuilder` instead of `WebApplicationBuilder`.
Verify Ctrl+C cancellation, host disposal, output/log separation and exit results. Do not align it
to an ASP.NET host merely because another application's console is a web-hosted feature role.

### CLI Parser Host

A finite CLI may use a parser-owned dispatch lifecycle. Keep help/version and syntax failures from
constructing credentials or external clients. Defer validation and service resolution when the
selected command does not need them. Use the `dotnet-cli` skill for command semantics.

### Build-Conditional Host Contract

When a Debug-only runtime configuration or source-reference mode exists:

- make the build constraint explicit;
- fail with an actionable message in unsupported builds;
- test both supported Debug behavior and Release refusal;
- avoid a silent fallback with different security or persistence semantics.

### Conditional Transport Surface

Registration and mapping must agree for controllers, gRPC, MCP, hubs, Razor Pages and static files.
Treat static files and Razor Pages as endpoint categories during inventory. A disabled feature must
not leave discovery metadata or routes whose dependencies cannot resolve.

### Shared Infrastructure Deduplication

When several features require one cache, database, channel, gRPC stack or event-stream owner, use an
application-local idempotent `Ensure*` boundary or equivalent explicit state. Verify one registration
and one owner for every supported feature combination.

### Shutdown Policy Parity

Compare explicit shutdown timeouts and draining behavior across otherwise similar long-running
hosts. A missing timeout is an audit question, not automatically a defect: confirm configuration,
worker drain needs, orchestrator grace period and existing defaults before aligning it.

CasCap hosts use `CasCap:HostLifecycleConfig:ShutdownTimeoutMs` through
`AddApplicationHostLifecycle`. Keep Kubernetes `terminationGracePeriodSeconds` longer than the host
timeout, including any `PreStop` duration and a safety margin. Finite Jobs do not use the daemon
shutdown budget; bound them through Job deadlines and retry policy.

### Failure and Process Results

Trace effective process behavior rather than trusting a declared `Task<int>`. A host that wraps and
rethrows an unexpected exception does not return its trailing success value. Tests should assert the
actual process or entry-point outcome for success, cancellation, expected finite completion and
unexpected failure.

For Kubernetes daemons, distinguish top-level and background failures:

- the AppHost logs unexpected startup/direct failures once and returns one;
- requested shutdown or normal cancellation returns zero;
- background supervision marks a shared failure outcome before requesting `StopApplication`;
- the AppHost returns that outcome after `RunAsync` completes and cleanup finishes.

Inventory direct `AddHostedService` registrations separately. A service outside the shared
supervisor must mark the process outcome itself or use another owner that does; `StopHost` alone can
still produce a successful AppHost result.

Prefer `IBgFeature` for a long-running application worker when its registration is owned by an
enabled feature or role. Conditional registration can use `IBgFeature.AlwaysEnabled` when the
reusable worker should not depend on application feature-name constants. Keep startup initializers
as direct `IHostedService` implementations so their failures prevent startup.

Exact nonzero values are rarely useful for daemons; use one unless an external process contract
requires more. Jobs depend on zero versus nonzero for completion and retry behavior.

## Shared-Package Extraction Gate

Move code to a shared hosting package only when:

- at least two applications execute equivalent behavior;
- required dependencies are acceptable to every consumer;
- application policy can remain outside the shared API;
- tests can prove the primitive independently;
- extraction removes more complexity than it adds;
- versioning and rollout can follow the normal producer-to-consumer release train.

Otherwise retain aligned application-local code. Repetition in a composition root can be cheaper
and safer than a shared abstraction with branching policy.
