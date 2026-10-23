# Typed Controller Example

This .NET 10 JSON-only controller template assumes existing `WidgetService`, `WidgetResponse`
and `CreateWidgetRequest` application types. The service owns validation, persistence and DTO
projection; it returns DTOs, nullable values or mutation outcomes, not HTTP results.
Use separate files for the controller, service and each DTO.

```csharp
using Example.Models;
using Example.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;

namespace Example.Controllers;

/// <summary>Exposes widget reads and creation.</summary>
[ApiController]
[Authorize]
[Route("api/v1/widgets")]
[ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
public sealed class WidgetsController(WidgetService widgetSvc) : ControllerBase
{
    private const string GetWidgetRoute = "GetWidgetV1";

    /// <inheritdoc cref="WidgetService.GetByIdAsync"/>
    [HttpGet("{id}", Name = GetWidgetRoute)]
    public async Task<Results<Ok<WidgetResponse>, NotFound>> GetByIdAsync(
        string id,
        CancellationToken cancellationToken)
        => await widgetSvc.GetByIdAsync(id, cancellationToken) is { } widget
            ? TypedResults.Ok(widget)
            : TypedResults.NotFound();

    /// <inheritdoc cref="WidgetService.CreateAsync"/>
    [HttpPost]
    public async Task<CreatedAtRoute<WidgetResponse>> CreateAsync(
        [FromBody] CreateWidgetRequest request,
        CancellationToken cancellationToken)
    {
        var widget = await widgetSvc.CreateAsync(request, cancellationToken);
        return TypedResults.CreatedAtRoute(widget, GetWidgetRoute, new { id = widget.Id });
    }
}
```

The read action infers 200 with a `WidgetResponse` body and 404. Creation infers 201 and
generates Location from the named read route. No duplicate success/not-found response attributes
are needed. The controller-level 400 describes automatic binding/validation errors that are outside
those result signatures; all actions in this example have bound input.

For a service with expected invalid/conflict/unsupported outcomes, switch on its typed outcome in
the controller and return the matching declared result. Do not turn normal absence into an exception.
The [typed outcome extension](../examples/typed-outcomes.md) supplies a concrete create-action
replacement and explains its 400/409 body and media-type distinctions.
Add an explicit response attribute for a middleware-generated 409 or a dynamic status only when
the application actually implements it. Authentication/authorization responses and descriptions
should likewise match the real scheme and configured documentation pipeline.

In a new host, register `AddControllers()`, the service and the application's authentication/
authorization scheme; map controllers after the existing security middleware. Reuse centralized
Problem Details handling. For optional first-party OpenAPI generation, reference the matching
`Microsoft.AspNetCore.OpenApi` package, enable `GenerateDocumentationFile`, call `AddOpenApi()`,
and map `MapOpenApi()` under the appropriate access policy.

The example's inherited XML comments are the summary source only when the configured OpenAPI
generator consumes them. Preserve an existing explicit `EndpointSummary` during a migration;
do not assume adding `inheritdoc` alone configures documentation generation.

Verify with approved HTTP tests and API Explorer/generated-document assertions: 200/404/201/400
responses, body schemas, validation payloads, authorization and a successful GET of the returned
Location. If using `ActionResult<T>` instead, keep MVC response annotations appropriate to that
style and verify content negotiation rather than assuming the typed-result rules apply.
