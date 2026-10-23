# Typed Invalid and Conflict Outcomes

This extends the existing [controller example](../references/controller-example.md), not a second
controller scaffold. It assumes the same authenticated .NET 10 JSON API, named GET route,
`WidgetResponse` and `CreateWidgetRequest` types. Preserve the host's security and Problem Details
configuration.

## Service Contract

If the service already has an equivalent outcome, use it instead of introducing this illustrative
type. Place this closed outcome model in its own `Models/CreateWidgetOutcome.cs` file:

```csharp
namespace Example.Models;

/// <summary>Describes expected widget creation outcomes without HTTP dependencies.</summary>
public abstract record CreateWidgetOutcome
{
    private CreateWidgetOutcome() { }

    /// <summary>Contains the created widget DTO.</summary>
    public sealed record Created(WidgetResponse Widget) : CreateWidgetOutcome;

    /// <summary>Contains safe, field-keyed business validation messages.</summary>
    public sealed record Invalid(Dictionary<string, string[]> Errors) : CreateWidgetOutcome;

    /// <summary>Indicates that creation conflicts with an existing resource.</summary>
    public sealed record AlreadyExists : CreateWidgetOutcome;
}
```

The service method now returns `Task<CreateWidgetOutcome>`. It owns validation, duplicate detection,
persistence and the DTO projection. Return a non-empty safe error dictionary for `Invalid`; do not
expose entity data or provider exception text. Let cancellation and unexpected failures propagate
to the host's existing handling rather than converting them into expected outcomes.

## Replace Only the Create Action

Keep the controller attributes, constructor and named GET action from the original example.
Add `System.Diagnostics` to its imports and replace its create action with:

```csharp
/// <inheritdoc cref="WidgetService.CreateAsync"/>
[HttpPost]
public async Task<Results<CreatedAtRoute<WidgetResponse>, ValidationProblem, Conflict<ProblemDetails>>> CreateAsync(
    [FromBody] CreateWidgetRequest request,
    CancellationToken cancellationToken)
{
    var outcome = await widgetSvc.CreateAsync(request, cancellationToken);
    return outcome switch
    {
        CreateWidgetOutcome.Created created =>
            TypedResults.CreatedAtRoute(created.Widget, GetWidgetRoute, new { id = created.Widget.Id }),
        CreateWidgetOutcome.Invalid invalid =>
            TypedResults.ValidationProblem(invalid.Errors),
        CreateWidgetOutcome.AlreadyExists =>
            TypedResults.Conflict(new ProblemDetails
            {
                Status = StatusCodes.Status409Conflict,
                Title = "A widget with this name already exists."
            }),
        _ => throw new UnreachableException("The service returned an unsupported creation outcome.")
    };
}
```

This is one service call followed by HTTP mapping, with no controller persistence or logging.
The unreachable branch catches a broken service contract, not normal absence or invalid input.
No broad `catch` turns programming errors into 400 or 409.

## Wire Contract

| Branch | HTTP status | Body and media type |
| --- | --- | --- |
| Created | 201 | Widget DTO, `application/json`, Location generated from the existing named GET route |
| Business invalid | 400 | Validation Problem Details with safe field errors, `application/problem+json` |
| Already exists | 409 | ProblemDetails-shaped JSON, `application/json` for this concrete `Conflict<ProblemDetails>` result |
| Binding/attribute validation | 400 | Automatic MVC Validation Problem Details before service invocation |
| Missing/insufficient identity | 401/403 | Defined by the host's authentication scheme, not the service outcome |

Using a `ProblemDetails` body inside `Conflict<T>` does **not** by itself select
`application/problem+json`. If the API requires that media type for 409, use the host's established
problem-result pattern and explicit metadata for its dynamic status, then test it. Do not advertise
a content type different from the actual typed result.

The union supplies success, business-validation and conflict metadata. Keep the original
controller's automatic-validation metadata for the GET and MVC pipeline; avoid adding duplicate
per-action attributes. Check API Explorer or the configured OpenAPI output, not reflection alone.
This example adds no enum or custom serializer contract.

## Validation Matrix

With approval, use an isolated HTTP fixture with a fake domain service and a fixture authentication
scheme; never use a production database merely to exercise mapping:

For a positional request record, put MVC validation attributes on its constructor parameter
(for example `CreateWidgetRequest([Required] string Name)`), not on the generated property with
`[property: Required]`. The latter can cause MVC validation to fail before the action executes.
Reuse the real request DTO's validation contract; do not weaken it to make the fixture pass.

* Created returns 201, and following Location reaches the expected GET resource.
* Invalid returns 400 with the expected error key and problem media type.
* Conflict returns 409 with status/title, no leaked detail, and the actual JSON media type.
* Missing/invalid request data is rejected before calling the fake service.
* Unauthenticated and forbidden calls do not invoke the service.
* The action forwards cancellation and an unexpected service failure is not rewritten as success.
* API Explorer reports 201/400/409 with the corresponding body types.

Direct method calls verify mapping but not MVC execution, authentication, route generation or
documentation inference. Distinguish those checks from actual HTTP evidence and from a generated
OpenAPI document, which requires the consuming host's configured generator.
