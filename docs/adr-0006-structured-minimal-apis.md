# Structured Minimal APIs for Native AOT

Status: Proposed. Date: 2026-11-07.

Tracking: [issue #54](https://github.com/f2calv/.github/issues/54).

## Scope and Current State

Investigate a structured Minimal API option for explicitly selected Native AOT HTTP hosts.
Retain controllers as the supported default for managed application APIs. This proposal does
not authorize application migrations, dependency installation, builds, tests or publishing.

The initial ownership review and documentation comparison are complete. No representative
application has been built or native-published. No framework/package combination is validated
by this record. Exact versions, adoption evidence and runtime verification remain open.

## Ownership Review

| Existing owner | Current responsibility | Proposed boundary |
| --- | --- | --- |
| [Web API instructions](../.github/instructions/dotnet.webapi.instructions.md) | Controller default, thin HTTP adapters and DTO invariants | Retain shared invariants; clarify adapter-neutral wording only when the companion is ready |
| [Web API skill](../.github/skills/dotnet-webapi/SKILL.md) | Controller workflow and HTTP contracts | Retain controller-specific registration, binding and migration guidance |
| [Contract details](../.github/skills/dotnet-webapi/references/contract-details.md) | JSON, metadata, caching, authorization, versioning and validation contracts | Reuse shared semantics; distinguish MVC mechanisms from Minimal API mechanisms |
| [Native AOT skill](../.github/skills/dotnet-aot/SKILL.md) | Compatibility assessment, generators, native publication and artifact proof | Own deployment compatibility gates, not endpoint organization |
| [AppHost skill](../.github/skills/dotnet-apphost/SKILL.md) | Composition, feature wiring, middleware order and lifecycle | Own host orchestration, not handler implementations |

The gap is endpoint organization and implementation for the existing AOT exception. The current
controller conversion workflow is not suitable for those hosts. The instructions also say HTTP
results belong in controllers even while allowing thin Minimal API handlers; the eventual edit
should describe HTTP adapters without allowing framework results into services.

## Proposed Direction

Use first-party route groups with explicit feature-specific registration as the first pilot.
Create a companion `dotnet-minimal-api` skill after the pilot meets its compatibility gates.
This name is proposed; no such skill exists yet.

A companion gives controller and Minimal API work separate discovery triggers and avoids
mixing MVC registration/model binding with request-delegate generation. Shared HTTP semantics
remain in one linked reference rather than being copied. Extending `dotnet-webapi` remains an
option if the pilot shows that maintaining separate adapter workflows adds more confusion than
it removes. Neither option changes the managed-host controller default implicitly.

The hypothesis is that explicit route groups provide sufficient endpoint ownership without a
new discovery framework. Falsify it with the same representative contract implemented using
FastEndpoints: compare registration clarity, validation/error behavior, generated artifacts,
native diagnostics and maintenance cost, not merely handler line counts.

## Alternatives

| Arrangement | Adoption and ergonomics | Dependency and maintenance cost | AOT evidence and current disposition |
| --- | --- | --- | --- |
| Built-in route groups and feature registration | First-party API; endpoints can live outside Program; group metadata reduces repetition | No endpoint-framework dependency; application owns explicit registration and validation setup | Microsoft documents the AOT route, but Minimal API support is partial; preferred pilot, not yet validated |
| FastEndpoints | Endpoint-oriented framework with its own registration, binding and testing conventions | Framework plus generator and selected validation/OpenAPI/testing extensions; generated-file and tooling lifecycle | Upstream documents AOT setup; exact versions and extension closure are unverified; retain as comparison candidate |
| Small custom arrangement | Can match existing feature boundaries | Plain application-owned registration is reasonable; a registry, discovery engine or generic endpoint base introduces local framework maintenance | No independent compatibility assurance; defer framework-building unless a demonstrated gap survives the pilot |
| Retain MVC | Existing managed contracts and familiar tooling | Avoids migration cost but does not provide a native HTTP host | Microsoft lists MVC as unsupported under Native AOT; retain for managed workloads |

No adoption statistics, release cadence or benchmark figures have been measured. Before accepting
an external framework, inspect its release history, supported target frameworks, issue handling,
license and exact package dependencies. Popularity alone is not a compatibility gate.

## Documentation Evidence

Sources were read on 2026-11-07. Microsoft links select the .NET 10 documentation view.
FastEndpoints documentation is rolling, not proof for a particular NuGet release. Pin upstream
source revisions and package versions during the executable comparison.

| Source | Observed documentation | Limit of the evidence |
| --- | --- | --- |
| [ASP.NET Core Native AOT support](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/native-aot?view=aspnetcore-10.0) | MVC unsupported, Minimal APIs partially supported; generated JSON metadata and testing the published artifact required | Does not certify a complete application or every authentication scheme |
| [Route groups](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/route-handlers?view=aspnetcore-10.0#route-groups) | MapGroup shares prefixes and metadata; endpoint registration can live outside Program | Does not prove every delegate/binding/filter shape works with request-delegate generation |
| [FastEndpoints AOT setup](https://fast-endpoints.com/docs/native-aot#project-setup) | Generator-discovered types, generated serializer contexts and binding reflection metadata are registered explicitly | Exact framework/generator versions and custom validators/converters still need verification |
| [FastEndpoints serializer generation](https://fast-endpoints.com/docs/native-aot#jsonserializercontext-generation) | Serializer context generation uses development-time tooling and generated files checked into source control | Adds reproducibility and generated-file maintenance work; not equivalent to ordinary incremental generation |
| [FastEndpoints OpenAPI export](https://fast-endpoints.com/docs/native-aot#export-openapi-documents) | Documents generated by a temporary managed app before native publication can be served statically | Static exported documents are not proof of live native OpenAPI generation |
| [FastEndpoints native testing](https://fast-endpoints.com/docs/native-aot#testing-native-aot-builds) | Native artifacts require black-box testing; its testing extension documents a dual mode | A managed WebApplicationFactory run is not artifact proof; caching and extension versions must be checked |

## Pilot Shape

Use a synthetic widget feature with a typed service and explicit DI registration. Keep one
feature-specific endpoint registration file and separate DTO/service types. The host invokes
registration directly; no assembly scans, runtime module discovery or generic endpoint registry.
Use direct, statically visible handler signatures and inspect generated request delegates.

The feature gate controls both service registration and route mapping. When disabled, the
feature's routes must be absent and return 404 rather than failing DI resolution. Do not treat
route hiding as authorization. Apply group policies and endpoint exceptions explicitly.

The contract should contain lookup, creation, invalid/conflict outcomes and an incremental
stream. Handlers perform one typed service call and map its outcome to concrete TypedResults
unions. Services remain HTTP-framework-neutral. Follow existing cancellation, error, logging
and privacy owners rather than reproducing their rules here.

## Compatibility and Contract Gates

The pilot is not a template until every applicable row has exact-version evidence.

| Concern | Required discriminator |
| --- | --- |
| Publication | Record SDK, TFM, RID, native toolchain, framework/runtime and direct/transitive package versions; inspect complete Release trimming/AOT diagnostics |
| Request delegates | Confirm generated code for each real mapping shape, DI parameter, custom binding and filter; reject unbounded runtime discovery |
| JSON | Generated metadata covers request/response roots, collections, stream elements, Problem Details, polymorphic subtypes and compatible enum converters; exercise every body shape |
| Configuration | Inspect binding and options-validation generator output independently of JSON; test changed file/environment values and invalid startup options |
| Validation | Verify .NET 10 Minimal API validation registration/generator behavior, required/missing/null inputs, nested values and domain failures; do not assume ApiController behavior transfers |
| Authentication and authorization | Verify the exact scheme/package with target-version support evidence; test anonymous, unauthenticated, forbidden and permitted callers plus resource policies |
| Errors | Preserve status, body and application/problem+json for validation/domain/unexpected failures, including non-JSON Accept headers; do not assume binding failures pass through handler filters |
| Cancellation and streaming | Demonstrate incremental delivery, cancellation propagation, pre-header acquisition failures and post-header failure/disposal behavior |
| Routes and versioning | Preserve method/path/constraints, names, operation IDs, version selection and Location escaping; verify any versioning extension separately |
| OpenAPI | Inspect actual generated documents and schemas, inferred unions and middleware errors; distinguish live native generation from managed build-time export |
| Feature gating and DI | Test enabled and disabled compositions; disabled routes absent, enabled services resolve with correct lifetimes |

Use the [Native AOT skill](../.github/skills/dotnet-aot/SKILL.md) for publication procedure and
diagnostic handling. Reverify .NET 11 and subsequent releases independently; a documentation
view or shared API name is not evidence that the .NET 10 result transfers.

## Migration and Test Plan

Capture the controller baseline before rewriting its adapter. Preserve methods, paths, names,
binding sources/defaults, validation status and error keys, JSON options, content types, auth
challenges, version behavior, headers and creation Location. Separate migration from a deliberate
versioned contract change; content negotiation or MVC-only features may justify retaining MVC.

Use unit tests for typed service outcomes and focused handler mappings. Reuse a shared black-box
HTTP suite against separately published managed and native executables with identical synthetic
configuration and fixtures. A WebApplicationFactory suite can supplement this, but cannot replace
published-artifact checks. Include malformed JSON, omitted required values, all auth outcomes,
disabled features, streaming/cancellation and OpenAPI retrieval or exported-file inspection.

Ask separately for the selected builds/native publications and test runs before executing them.
Choose a supported local RID and existing toolchain; do not install a toolchain or start services
implicitly. Record executed test counts, artifact identity, exact commands and diagnostics. If a
toolchain is unavailable, report the matrix row as unverified rather than replacing native proof
with a normal build.

## Subsequent Application Review

After the skill is complete, a separately requested workspace review will inventory controller
usage across application hosts and assess migration merits individually. The intended deployment
goal is faster startup through Native AOT alongside adoption of .NET 11 wherever feasible, not
uniform conversion to Minimal APIs. Retain .NET 10 as the baseline required by issue #54 and
prioritize exact-version .NET 11 verification before recommending application migrations.

The skill must enable a per-host decision: AOT candidate, blocked with concrete dependencies or
features, or retain managed hosting because migration cost or contract loss outweighs the benefit.
Assess the entire executable closure, including other transports, authentication, persistence,
serializers and runtime discovery; converting controllers alone does not establish AOT readiness.
Choose representative pilot contracts from the later authorized inventory rather than assuming
the synthetic example covers every application.

For each candidate, compare cold process start to readiness and first successful representative
request on identical hardware, configuration and dependency conditions. Record repeated runs,
artifact identity, memory and representative steady-state latency/throughput alongside migration
effort. Separate framework-upgrade effects from AOT effects by comparing managed and native
artifacts on the same .NET version. Recommend adoption only with preserved HTTP contracts and
measured benefit; keep blocked or disproportionate workloads managed. This review and its
benchmarks are future work, not authorization granted by the current investigation.

## Delivery Phases

- [x] Review existing Web API, Native AOT and AppHost ownership and identify the local gap.
- [x] Compare documented organization and generator/tooling costs without certifying compatibility.
- [ ] Verify framework adoption/maintenance evidence and select exact dependency versions.
- [ ] Obtain build/native-publish and test consent for a bounded representative comparison.
- [ ] Implement equivalent first-party and FastEndpoints pilots; record exact compatibility results.
- [ ] Accept or revise the approach and companion-versus-extension decision from those results.
- [ ] Author the owning skill and representative examples; link shared contract semantics and clarify scoped instructions.
- [ ] Add focused structural/regression checks, metadata and versions through the skill-library workflow.
- [ ] Verify discovery descriptions, links, executed test counts and required repository validation.

The issue remains open. Its final acceptance criteria are not met by this documentation phase.
No existing skill, instruction or package version changes in this phase.

## Revisit Triggers

Recheck when ASP.NET feature support, framework versions, request-delegate/validation/configuration
generators, JSON metadata, authentication or versioning extensions change. Recheck FastEndpoints
generator tooling, generated-file policy, OpenAPI exports and testing caches independently.
Revisit the companion boundary if shared HTTP semantics diverge or discovery selects the wrong
adapter workflow. Performance claims require measurements on equivalent configurations.

## Handover

Next: choose exact .NET 10 and framework/extension versions, verify authoritative validation and
OpenAPI generator documentation, then obtain approval for the pilot build and test matrix.
Once the skill is complete, await the separate application-review request and use the criteria
above to assess .NET 11 Native AOT adoption across the selected workspace hosts.
The canonical local decision record is this proposed ADR; issue #54 remains the delivery tracker.
No remote issue checklist or comment has been changed.
