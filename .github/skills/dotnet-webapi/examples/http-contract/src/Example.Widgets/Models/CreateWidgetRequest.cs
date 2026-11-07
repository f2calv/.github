namespace Example.Widgets.Models;

/// <summary>The create request accepted by both HTTP adapters.</summary>
public sealed record CreateWidgetRequest
{
    /// <summary>The requested synthetic name; the service rejects empty names.</summary>
    /// <example>created-widget</example>
    public string? Name { get; init; }
}
