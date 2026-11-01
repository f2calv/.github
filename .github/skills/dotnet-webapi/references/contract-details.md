# Contract Details

Detailed JSON, OpenAPI, caching, authorization and DTO validation rules behind the always-on
[Web API instructions](../../../instructions/dotnet.webapi.instructions.md).

## Controller Contracts

- **String enums on the JSON wire**: configure `JsonStringEnumConverter` in both HTTP JSON options
  (used by `TypedResults`) and MVC JSON options (used by controller request binding). Configure
  converters once in the owning registration path, not per action. Verify actual JSON and generated
  schemas; `AddJsonOptions` alone does not configure typed responses. Normalize automatic validation
  failures to `ValidationProblemDetails`. For team-owned consumers, migrate deliberately to the
  supported contract rather than adding numeric-enum or legacy-error compatibility shims.
- **Avoid duplicate response metadata**: concrete typed results and their unions infer status codes
  and body types in controllers. Add `ProducesResponseType` only for responses the signature cannot
  describe, such as automatic validation, exception-handler responses or dynamic status codes.
  Share genuinely common metadata at controller scope. Keep stable route/operation names and existing
  summaries; XML comments supply OpenAPI text only when the generator is configured to consume them.
  Use the [Web API skill](../SKILL.md) for the workflow and worked example.
  Verify closed generic controllers through `ApiExplorer`: shared error metadata can hide an
  inferred success DTO. If it does, repair only that module's metadata rather than adding global
  response conventions or assuming a successful build proves the OpenAPI contract.
- **Private source content is not cacheable by default**: emit `Cache-Control: no-store` on private
  document/source responses unless an explicit access- and retention-aware caching policy requires
  otherwise. Cookie authorization alone is not a cache policy. Verify headers on actual content
  responses, not only endpoint attributes.
- **Resource authorization and schemes**: manual resource-aware authorization must authenticate
  the policy's named schemes before evaluating its requirements, using the framework policy
  evaluator. `IAuthorizationService` alone does not select authentication schemes; adding browser
  cookies must not replace an existing machine API's authentication defaults.
- **API versioning registration**: do not restate Asp.Versioning defaults. Omit
  `DefaultApiVersion = new ApiVersion(1.0)` (AV0011), and omit `AddEndpointsApiExplorer()` when
  `AddApiExplorer()` is already registered (AV0020).

## Request and Response DTOs

- Give every public DTO property a `/// <example>value</example>` tag so OpenAPI documents realistic
  examples.
- Require non-nullable value-type request properties explicitly with `[JsonRequired]`, `required` or
  a validated nullable-input pattern. Never let an omitted member silently bind to `0`, `false` or a
  default enum value when the caller must choose it.
  For required query parameters, including struct-backed value objects, use binding validation such
  as `[BindRequired]`; test omission separately from empty and malformed values because omission
  can otherwise supply `default(T)` without a model-state error.
  Validate integral bounds without floating-point rounding: a large `long` limit can select a
  double-based `Range` overload and lose precision. Use typed integral bounds or explicit integer
  validation, and test the exact accepted/rejected boundary values over HTTP.
