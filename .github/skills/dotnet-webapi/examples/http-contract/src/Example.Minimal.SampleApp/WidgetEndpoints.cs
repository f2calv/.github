using Example.Widgets.Models;
using Example.Widgets.Services;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace Example.Minimal.SampleApp;

/// <summary>Explicitly registers the synthetic widget feature.</summary>
internal static class WidgetEndpoints
{
    /// <summary>Maps the feature's read, create and stream contracts.</summary>
    public static void Map(IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/widgets");
        group.MapGet("/{id:int}", GetByIdAsync).WithName("GetWidget");
        group.MapPost("/", CreateAsync)
            .Produces<ProblemDetails>(StatusCodes.Status409Conflict, "application/problem+json");
        group.MapGet("/{id:int}/content", OpenContentAsync);
    }

    private static async Task<Results<Ok<WidgetResponse>, NotFound>> GetByIdAsync(
        int id,
        WidgetService widgetSvc,
        CancellationToken cancellationToken)
        => await widgetSvc.GetByIdAsync(id, cancellationToken) is { } widget
            ? TypedResults.Ok(widget)
            : TypedResults.NotFound();

    private static async Task<Results<CreatedAtRoute<WidgetResponse>, ValidationProblem, ProblemHttpResult>> CreateAsync(
        CreateWidgetRequest request,
        WidgetService widgetSvc,
        CancellationToken cancellationToken)
        => await widgetSvc.CreateAsync(request, cancellationToken) switch
        {
            { Status: CreateWidgetStatus.Created, Widget: { } widget } =>
                TypedResults.CreatedAtRoute(widget, "GetWidget", new RouteValueDictionary { ["id"] = widget.Id }),
            { Status: CreateWidgetStatus.Invalid, Errors: { } errors } => TypedResults.ValidationProblem(errors),
            { Status: CreateWidgetStatus.Conflict } => TypedResults.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Widget already exists."),
            _ => throw new UnreachableException()
        };

    private static async Task<Results<FileStreamHttpResult, NotFound>> OpenContentAsync(
        int id,
        WidgetService widgetSvc,
        CancellationToken cancellationToken)
        => await widgetSvc.OpenContentAsync(id, cancellationToken) is { } stream
            ? TypedResults.File(stream, "application/octet-stream", "widget.txt")
            : TypedResults.NotFound();
}
