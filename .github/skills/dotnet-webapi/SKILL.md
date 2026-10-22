---
name: dotnet-webapi
description: 'Create, migrate and validate ASP.NET Core controller Web APIs, TypedResults, DTO services, authorization, validation, streaming and OpenAPI response metadata. Use when modifying controllers, HTTP contracts or minimal-to-controller migrations.'
---

# ASP.NET Core Web API

Build thin controller APIs with explicit HTTP semantics and verified documentation. Standardize
team-owned JSON APIs on `TypedResults`, string enum values and validation Problem Details.
Controllers remain the application default rather than following the minimal-API template trend.
MVC `ActionResult<T>` is reserved for an explicit output-formatter/content-negotiation requirement.

## Authorities

- [Web API instructions](../../instructions/dotnet.webapi.instructions.md) own controller boundaries
  and metadata conventions.
- [C# instructions](../../instructions/dotnet.csharp.instructions.md) own types, DI, cancellation,
  logging and errors. Do not introduce an interface solely because a type is a service.
- [Testing instructions](../../instructions/dotnet.testing.instructions.md) own test approval and
  fixtures. Use the test-platform skill for the repository's runner.
- [REST Client skill](../rest-client-requests/SKILL.md) owns request-file layout and secret handling.

These repository-owned authorities take precedence over conflicting generic/plugin defaults.
Do not edit a generated plugin installation to store shared conventions.

## Workflow

### 1. Establish the Contract

Read host registration, middleware, related controllers, service methods, DTOs, routes, client code,
authorization policies, serializer options and protocol tests before editing.

For migrations, inventory method/path pairs, named endpoints, status/body combinations, validation,
content types, Location headers and streaming behavior. Keep the migration separate from a versioned
contract change. Controllers are the application default; health and protocol mappings can remain
minimal.

### 2. Place Responsibilities

| Layer | Owns |
| --- | --- |
| Controller | Routing, binding, authorization metadata, one service call, outcome-to-HTTP mapping and response headers |
| Service | Business validation, orchestration, persistence, logging and entity/domain-to-DTO projection |
| DTO/outcome | Transport-safe values and explicit success/missing/conflict/invalid states, not framework response objects |
| Host extensions | DI registration and API policies; application-owned extensions use the application namespace |
| Error handler | Explicit domain-exception mappings and sanitized Problem Details before the response starts |

Use nullable results for expected absence, booleans for simple mutations, and an existing typed
outcome for multi-branch operations. Do not invent a generic result framework, duplicate service
interfaces or add an HTTP-adapter layer that merely moves `TypedResults` out of the controller.
Keep nontrivial DTO projections outside controllers.

### 3. Choose Results and Metadata

Use the [controller example](./references/controller-example.md). For JSON-only endpoints, return
`Ok<T>`, `CreatedAtRoute<T>`, `NoContent` or an explicit `Results<T1, T2, ...>` union, constructed
with `TypedResults`. This provides compile-time checks and response metadata in MVC too.

| Concern | Default |
| --- | --- |
| Success and declared alternatives | Infer from concrete results/unions; do not repeat `ProducesResponseType` |
| Automatic model validation | `[ApiController]`; document validation Problem Details where applicable |
| Exceptions mapped outside the action | Explicit response metadata for the mapped status/body |
| `StatusCodeHttpResult` or configurable `ProblemHttpResult` | Document actual possible codes; the CLR type alone cannot identify them |
| Shared metadata | Controller scope only when true for every action |
| Summary/description | Service XML docs inherited by thin actions; verify generator support before relying on them |
| Existing endpoint name/summary | Preserve during migration; names and summaries are not inferred from response types |
| Resource creation | 201 with a resolvable Location; prefer named-route generation for new APIs |
| Existing Location format | Preserve relative/absolute URI behavior and escaping when compatibility matters |
| Content negotiation | Use MVC `ActionResult<T>` and document its response alternatives |

`HttpResults` execute through `IResult`, bypass MVC output formatters and use HTTP JSON options.
MVC request-body binding still uses MVC input formatters. Inspect both JSON option sets: changing
result styles must not silently change casing, enum values, converters or null handling.
`Produces`/`Consumes` are not substitutes for testing the actual content types.

Apply the shared string-enum convention to both pipelines, retaining other intentional options:

```csharp
services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
services.AddControllers().AddJsonOptions(options =>
    options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()));
```

The sample requires `System.Text.Json.Serialization`. Register each converter once.
Capture actual enum-bearing response bodies, request binding and OpenAPI enum schemas in focused
tests. During an authorized standardization of team-owned APIs, update consumers to string values
and `ValidationProblemDetails`; do not preserve superseded formats with compatibility shims.
Do not independently disable numeric input acceptance unless that stricter validation is requested.

`[ApiController]` validates controller-bound DTOs without minimal API `AddValidation()`. Keep
explicit request constraints, missing-body behavior and intentional nullable-input semantics.
Do not harden an existing serializer or change published DTO types incidentally.

### 4. Wire Security, Errors and Streaming

Preserve separate policies and derive actor/tenant identity from validated claims, not request
bodies. Register policies and middleware consistently with controller attributes. Anonymous
Development access must be explicit; do not loosen Production to make tests pass.

Use existing exception handlers and Problem Details. Do not map all `ArgumentException` or
`InvalidOperationException` instances to client errors: these can be programming faults. Map
specific domain failures and keep details safe. Account for .NET 10 handled-exception diagnostics
suppression, avoiding both missing telemetry and duplicate logging.

Pass cancellation through every asynchronous call. Return `IAsyncEnumerable<T>` without collecting
it into a list. If acquisition can fail, acquire or prime before committing success headers.
Once streaming starts, middleware cannot replace the status; preserve the protocol's cancellation,
failure and task-disposal behavior rather than promising transparent recovery.

### 5. Verify Documentation and Behavior

Reuse the existing OpenAPI pipeline. For new .NET 10 hosts, prefer the first-party
`Microsoft.AspNetCore.OpenApi` package with `AddOpenApi()` and `MapOpenApi()`. It is a package
dependency, not an automatically available shared-framework API. Do not remove a supported
existing generator simply because another generator is preferred for new projects.

Enable `GenerateDocumentationFile` when using XML comments. Check generated summaries,
`inheritdoc`, request/response schemas and operation IDs with the actual generator.
Protect or restrict the document endpoint according to the application's audience.
Do not introduce a generator/UI as incidental work in a controller-only migration.

Build the smallest affected project, then run approved focused tests. Verify:

- All expected actions are controllers and method/path/name/policy mappings remain correct.
- Actual HTTP status codes, JSON shapes, validation errors and Location targets match the contract.
- Streaming is incremental and ownership failures still surface before success.
- API Explorer or the configured OpenAPI document contains inferred success/error responses and
  explicit middleware/dynamic responses. Reflection over attributes alone is not enough.
- If a generator is configured, inspect its generated document as well; API Explorer assertions
  alone do not prove generated OpenAPI correctness.

Update affected READMEs and request examples. Do not commit, push, deploy, run live requests or
execute tests without the applicable authorization.

## Sources

Use the target framework's current Microsoft documentation, not recommendations from popularity
rankings or older templates:

- [Controller return types, including typed results and metadata inference](https://learn.microsoft.com/aspnet/core/web-api/action-return-types?view=aspnetcore-10.0#resultstresult1-tresultn-type)
- [OpenAPI metadata](https://learn.microsoft.com/aspnet/core/fundamentals/openapi/include-metadata?view=aspnetcore-10.0)
- [OpenAPI package and setup](https://learn.microsoft.com/aspnet/core/fundamentals/openapi/overview?view=aspnetcore-10.0)
- [XML documentation integration](https://learn.microsoft.com/aspnet/core/fundamentals/openapi/openapi-comments?view=aspnetcore-10.0)
- [API errors and Problem Details](https://learn.microsoft.com/aspnet/core/web-api/handle-errors?view=aspnetcore-10.0)

## Maintaining This Skill

- Recheck controller typed-result metadata inference, API Explorer and generator behavior on framework upgrades.
- Recheck HTTP/MVC string-enum option alignment and generated schemas when serializer registration changes.
- Recheck first-party OpenAPI package requirements, XML source-generator support and named-route APIs.
- Recheck handled-exception telemetry defaults and streaming serialization/cancellation semantics.
- Keep the worked example aligned with shared controller and service-boundary instructions.
