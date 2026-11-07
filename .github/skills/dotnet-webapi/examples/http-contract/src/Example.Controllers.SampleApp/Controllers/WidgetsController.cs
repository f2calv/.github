using Example.Widgets.Models;
using Example.Widgets.Services;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace Example.Controllers.SampleApp.Controllers;

/// <summary>The managed MVC adapter for the synthetic widget feature.</summary>
[ApiController]
[Route("api/v1/widgets")]
public sealed class WidgetsController(WidgetService widgetSvc) : ControllerBase
{
    /// <summary>Returns a widget by its synthetic identifier.</summary>
    [HttpGet("{id:int}", Name = "GetWidget")]
    public async Task<Results<Ok<WidgetResponse>, NotFound>> GetByIdAsync(int id, CancellationToken cancellationToken)
        => await widgetSvc.GetByIdAsync(id, cancellationToken) is { } widget
            ? TypedResults.Ok(widget)
            : TypedResults.NotFound();

    /// <summary>Creates a widget or maps a domain failure to a concrete HTTP result.</summary>
    [HttpPost]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<Results<CreatedAtRoute<WidgetResponse>, ValidationProblem, ProblemHttpResult>> CreateAsync(
        CreateWidgetRequest request,
        CancellationToken cancellationToken)
        => await widgetSvc.CreateAsync(request, cancellationToken) switch
        {
            { Status: CreateWidgetStatus.Created, Widget: { } widget } =>
                TypedResults.CreatedAtRoute(widget, "GetWidget", new { id = widget.Id }),
            { Status: CreateWidgetStatus.Invalid, Errors: { } errors } => TypedResults.ValidationProblem(errors),
            { Status: CreateWidgetStatus.Conflict } => TypedResults.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Widget already exists."),
            _ => throw new UnreachableException()
        };

    /// <summary>Transfers the synthetic stream to a concrete HTTP result.</summary>
    [HttpGet("{id:int}/content")]
    public async Task<Results<FileStreamHttpResult, NotFound>> OpenContentAsync(int id, CancellationToken cancellationToken)
        => await widgetSvc.OpenContentAsync(id, cancellationToken) is { } stream
            ? TypedResults.File(stream, "application/octet-stream", "widget.txt")
            : TypedResults.NotFound();
}
