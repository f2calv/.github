---
description: 'ASP.NET Core controller, endpoint and request/response DTO conventions for thin pass-through controllers, typed service calls and OpenAPI examples.'
applyTo: '**/*Controller.cs,**/Controllers/**/*.cs,**/*Endpoints.cs,**/Models/**/*.cs,**/*Request.cs,**/*Response.cs,**/*Dto.cs'
---

# ASP.NET Core Web API

## Controllers and Endpoints

- **Thin pass-through**: delegate to a single service call and map the result to an HTTP response.
  No business logic, LINQ projections, dictionary lookups or logging in the controller.
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

## Request and Response DTOs

- Give every public DTO property a `/// <example>value</example>` tag so OpenAPI documents realistic
  examples.
- Require non-nullable value-type request properties explicitly with `[JsonRequired]`, `required` or
  a validated nullable-input pattern. Never let an omitted member silently bind to `0`, `false` or a
  default enum value when the caller must choose it.
