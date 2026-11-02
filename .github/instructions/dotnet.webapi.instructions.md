---
description: 'ASP.NET Core controller, endpoint and request/response DTO conventions for thin pass-through controllers, typed service calls and OpenAPI examples.'
applyTo: '**/*Controller.cs,**/Controllers/**/*.cs,**/*Endpoints.cs,**/*Request.cs,**/*Response.cs,**/*Dto.cs'
---

# ASP.NET Core Web API

## Controllers and Endpoints

- **Controllers are the default** for application Web APIs, new ones included; this overrides a
  generic minimal-API default. Minimal mappings suit only small host or protocol endpoints such as
  health checks. Convert an existing minimal API in its own focused change, preserving routes,
  authentication, validation, streaming and response contracts.
- **Thin pass-through**: one service call mapped to an HTTP result, with no business logic, LINQ
  projections, lookups or logging; permitted minimal handlers follow the same boundary.
- **HTTP results belong in controllers**: services return DTOs, nullable values or typed outcomes,
  never `IResult`. Use `TypedResults` with concrete unions such as
  `Results<Ok<WidgetResponse>, NotFound>`; `ActionResult<T>` only where output formatters or content
  negotiation are genuinely required.
- **String enums on the JSON wire**, configured once for both HTTP and MVC JSON options, with
  validation failures normalized to `ValidationProblemDetails`.
- **Avoid duplicate response metadata**: typed results infer status and body; add
  `ProducesResponseType` only for what the signature cannot describe, and verify OpenAPI through
  `ApiExplorer` rather than a successful build.
- **Logging lives in the service**; inject `ILogger` into a controller only for work it cannot
  delegate, such as a streaming loop.
- **Private source content is not cacheable**: emit `Cache-Control: no-store` unless an explicit
  caching policy says otherwise.
- **Typed service methods** own table names, queue keys and domain logging; controllers never call
  generic base methods such as `GetEntities<T>(tableName, ...)`.
- **Resource authorization** authenticates the policy's named schemes through the framework policy
  evaluator before evaluating requirements.
- **Expression bodies** for single-expression or single-`await` methods. Map nullable service
  results to `NotFound` with pattern matching rather than exceptions:

```csharp
public Results<Ok<Widget>, NotFound> GetWidget(int id)
    => widgetSvc.TryGetWidget(id) is { } widget
        ? TypedResults.Ok(widget)
        : TypedResults.NotFound();
```

- **Documentation**: thin controller methods use
  `/// <inheritdoc cref="ServiceType.Method(ParamTypes)"/>` rather than duplicating the service's
  XML documentation.
- **API versioning**: do not restate Asp.Versioning defaults (AV0011, AV0020).

## Request and Response DTOs

- Give every public DTO property a `/// <example>value</example>` tag.
- Never let an omitted required value bind silently to `0`, `false` or a default enum: require it
  with `[JsonRequired]`, `required` or `[BindRequired]`, and validate integral bounds exactly.

The `dotnet-webapi` skill's [contract details](../skills/dotnet-webapi/references/contract-details.md)
hold the full JSON, OpenAPI, caching, authorization and validation rules.
