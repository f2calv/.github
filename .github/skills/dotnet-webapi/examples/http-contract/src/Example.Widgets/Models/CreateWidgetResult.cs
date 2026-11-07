namespace Example.Widgets.Models;

/// <summary>A provider-neutral create outcome mapped to HTTP by each adapter.</summary>
public sealed record CreateWidgetResult
{
    /// <summary>The create outcome.</summary>
    public required CreateWidgetStatus Status { get; init; }

    /// <summary>The created widget, present only for a successful outcome.</summary>
    public WidgetResponse? Widget { get; init; }

    /// <summary>Domain validation errors, present only for an invalid outcome.</summary>
    public Dictionary<string, string[]>? Errors { get; init; }
}
