namespace Example.Widgets.Models;

/// <summary>A synthetic widget returned by the contract fixture.</summary>
public sealed record WidgetResponse
{
    /// <summary>The synthetic identifier.</summary>
    /// <example>1</example>
    public required int Id { get; init; }

    /// <summary>The synthetic display name.</summary>
    /// <example>example-widget</example>
    public required string Name { get; init; }
}
