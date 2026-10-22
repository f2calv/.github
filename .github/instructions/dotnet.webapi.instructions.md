---
description: 'ASP.NET Core controller, endpoint and request/response DTO conventions for thin pass-through controllers, typed service calls and OpenAPI examples.'
applyTo: '**/*Controller.cs,**/Controllers/**/*.cs,**/*Endpoints.cs,**/Models/**/*.cs,**/*Request.cs,**/*Response.cs,**/*Dto.cs'
---

# ASP.NET Core Web API

## Controllers and Endpoints

- **Controllers are the default** for application Web APIs, including new projects. Use minimal
  mappings only for small host/protocol endpoints, such as health checks, where a controller adds
  ceremony without useful structure. Do not choose minimal APIs merely because an application is
  new or its current endpoints use them. This repository convention takes precedence over a
  generic Web API skill's minimal-API default.
- **Keep migrations separate**: when standardizing an existing minimal application API, preserve
  its routes, authentication, validation, streaming and response contracts. Convert it to controllers
  in a focused change, not as incidental work during an unrelated behavior change.
- **Thin pass-through**: delegate to a single service call and map the result to an HTTP response.
  No business logic, LINQ projections, dictionary lookups or logging in the controller. The same
  boundary applies to permitted minimal handlers: move substantial mapping and orchestration into
  the application service rather than hiding a controller-sized implementation in a mapping extension.
- **Logging lives in the service**: domain-specific, request-specific logging belongs in the service
  method. Remove `ILogger` from a controller whose methods only delegate; inject it only for work that
  cannot be delegated, such as a streaming loop with `LogTrace`.
- **Typed service methods**: never call generic base-class methods (`GetEntities<T>(tableName, ...)`,
  `Enqueue<T>(obj, ...)`) from a controller. Add typed service methods that own table names, queue
  keys and domain logging, keeping controllers ignorant of infrastructure.
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
- **API versioning registration**: do not restate Asp.Versioning defaults. Omit
  `DefaultApiVersion = new ApiVersion(1.0)` (AV0011), and omit `AddEndpointsApiExplorer()` when
  `AddApiExplorer()` is already registered (AV0020).

## Request and Response DTOs

- Give every public DTO property a `/// <example>value</example>` tag so OpenAPI documents realistic
  examples.
- Require non-nullable value-type request properties explicitly with `[JsonRequired]`, `required` or
  a validated nullable-input pattern. Never let an omitted member silently bind to `0`, `false` or a
  default enum value when the caller must choose it.
