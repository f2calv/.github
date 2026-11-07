namespace Example.Widgets.Models;

/// <summary>The domain outcomes of creating a widget.</summary>
public enum CreateWidgetStatus
{
    /// <summary>A widget was created.</summary>
    Created,

    /// <summary>The name failed domain validation.</summary>
    Invalid,

    /// <summary>The name is already in use.</summary>
    Conflict
}
