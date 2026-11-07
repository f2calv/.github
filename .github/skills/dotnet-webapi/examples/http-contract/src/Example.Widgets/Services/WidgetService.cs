using Example.Widgets.Models;
using System.Text;

namespace Example.Widgets.Services;

/// <summary>Provides a thread-safe, in-memory synthetic store for the HTTP fixtures.</summary>
public sealed class WidgetService
{
    private readonly Lock _gate = new();
    private readonly Dictionary<int, WidgetResponse> _widgets = new()
    {
        [1] = new WidgetResponse { Id = 1, Name = "example-widget" }
    };

    /// <summary>Returns the known synthetic widget or null for an unknown identifier.</summary>
    public ValueTask<WidgetResponse?> GetByIdAsync(int id, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            return ValueTask.FromResult(_widgets.GetValueOrDefault(id));
        }
    }

    /// <summary>Validates and creates a widget without exposing HTTP framework types.</summary>
    public ValueTask<CreateWidgetResult> CreateAsync(CreateWidgetRequest request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return ValueTask.FromResult(new CreateWidgetResult
            {
                Status = CreateWidgetStatus.Invalid,
                Errors = new() { ["name"] = ["A name is required."] }
            });
        }

        lock (_gate)
        {
            if (_widgets.Values.Any(widget => widget.Name == request.Name))
            {
                return ValueTask.FromResult(new CreateWidgetResult { Status = CreateWidgetStatus.Conflict });
            }

            var widget = new WidgetResponse { Id = _widgets.Count + 1, Name = request.Name };
            _widgets.Add(widget.Id, widget);
            return ValueTask.FromResult(new CreateWidgetResult { Status = CreateWidgetStatus.Created, Widget = widget });
        }
    }

    /// <summary>Opens synthetic content or returns null when the widget is absent.</summary>
    public ValueTask<Stream?> OpenContentAsync(int id, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            return ValueTask.FromResult<Stream?>(_widgets.ContainsKey(id)
                ? new MemoryStream(Encoding.UTF8.GetBytes("synthetic-widget-content"), writable: false)
                : null);
        }
    }
}
