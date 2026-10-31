# Read-Only Runtime MCP Boundary

This is a host-integration example for `ModelContextProtocol.AspNetCore` **2.2.0**, targeting
.NET 10. It exposes one fixed-size runtime snapshot, not persisted history or write actions.
Keep the version in the consuming repository's central package file and refresh the SDK evidence
before adoption. The model sees no channel selector, configuration or user content.

## Host Prerequisites

The host must already authenticate requests through its approved identity stack. For remote use,
that includes the MCP-compatible OAuth discovery/challenge and HTTPS controls in the
[HTTP reference](../references/http-security.md), not merely validating a bearer token.

Register the application's **existing running snapshot source** as `IRuntimeSnapshotSource` before
calling `AddExampleMcp`. The interface is an application adapter contract, not an SDK type.
Implement it over the live service's synchronized snapshot API; do not instantiate another worker,
read upstream services or register a fixture returning empty state in production.

The source must return a detached snapshot at call time, `null` when its observation is unavailable,
and propagate cancellation/failure. Counts are observations, not readiness claims. It must complete
within the application's request budget and never log arguments or results.

## Application Adapter Contract

These files belong in the application's usual source project. Use its existing equivalent
contracts instead when available.

### `Abstractions/IRuntimeSnapshotSource.cs`

```csharp
using Example.Models;

namespace Example.Abstractions;

public interface IRuntimeSnapshotSource
{
    public ValueTask<RuntimeSnapshot?> GetSnapshotAsync(CancellationToken cancellationToken);
}
```

### `Models/RuntimeSnapshot.cs`

```csharp
namespace Example.Models;

public sealed record RuntimeSnapshot(DateTimeOffset ObservedAtUtc, int ActiveWorkers, long QueuedItems);
```

### `Models/McpConfig.cs`

```csharp
namespace Example.Models;

public sealed record McpConfig
{
    public const string ConfigurationSectionName = "Mcp";

    public bool Enabled { get; init; }
}
```

## MCP Files

### `Models/RuntimeMcpSnapshot.cs`

```csharp
using System.ComponentModel;

namespace Example.Models;

public sealed record RuntimeMcpSnapshot(
    [property: Description("UTC time when the running service observed these counts.")]
    DateTimeOffset ObservedAtUtc,
    [property: Description("Number of active worker instances; not a readiness assertion.")]
    int ActiveWorkers,
    [property: Description("Number of queued work items; excludes item identifiers and contents.")]
    long QueuedItems);
```

### `Services/RuntimeMcpService.cs`

```csharp
using Example.Abstractions;
using Example.Models;
using ModelContextProtocol;
using ModelContextProtocol.Server;
using System.ComponentModel;

namespace Example.Services;

[McpServerToolType]
public sealed class RuntimeMcpService(IRuntimeSnapshotSource runtimeSnapshotSource)
{
    [McpServerTool(Name = "get_runtime_snapshot", UseStructuredContent = true,
        ReadOnly = true, Destructive = false, Idempotent = true, OpenWorld = false)]
    [Description("Get current worker and queue counts from the running application.")]
    public async Task<RuntimeMcpSnapshot> GetRuntimeSnapshot(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var snapshot = await runtimeSnapshotSource.GetSnapshotAsync(cancellationToken);
        if (snapshot is null)
            throw new McpException("Runtime observation is unavailable. Wait for application startup and retry.");

        return new(snapshot.ObservedAtUtc, snapshot.ActiveWorkers, snapshot.QueuedItems);
    }
}
```

### `Extensions/McpEndpointExtensions.cs`

```csharp
using Example.Abstractions;
using Example.Models;
using Example.Services;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ModelContextProtocol.AspNetCore;

namespace Example.Extensions;

public static class McpEndpointExtensions
{
    private const string McpPath = "/mcp";
    private const string ReadPolicy = "McpRead";

    public static bool AddExampleMcp(this WebApplicationBuilder builder)
    {
        var config = builder.Configuration.GetSection(McpConfig.ConfigurationSectionName).Get<McpConfig>() ?? new();
        if (!config.Enabled)
            return false;

        if (!builder.Services.Any(service => service.ServiceType == typeof(IRuntimeSnapshotSource)))
            throw new InvalidOperationException("MCP requires the running application's snapshot source.");

        builder.Services.AddAuthorization(options =>
            options.AddPolicy(ReadPolicy, policy => policy
                .RequireAuthenticatedUser()
                .RequireClaim("permission", "runtime.read")));
        builder.Services.AddMcpServer()
            .WithHttpTransport(options => options.SessionMode = HttpServerSessionMode.Stateless)
            .WithTools<RuntimeMcpService>();
        return true;
    }

    public static void MapExampleMcp(this WebApplication app, bool enabled)
    {
        if (!enabled)
        {
            app.Use(async (context, next) =>
            {
                if (context.Request.Path.StartsWithSegments(McpPath))
                {
                    context.Response.StatusCode = StatusCodes.Status404NotFound;
                    return;
                }

                await next(context);
            });
            return;
        }

        var group = app.MapGroup(McpPath).RequireAuthorization(ReadPolicy);
        group.AddEndpointFilter(async (context, next) =>
        {
            if (context.HttpContext.Request.Headers.ContainsKey("Origin"))
                return Results.StatusCode(StatusCodes.Status403Forbidden);

            return await next(context);
        });
        group.MapMcp();
    }
}
```

## Composition

After the host's real authentication and snapshot-source registrations, call:

```csharp
var mcpEnabled = builder.AddExampleMcp();
var app = builder.Build();
app.MapExampleMcp(mcpEnabled);
app.UseAuthentication();
app.UseAuthorization();
// Map the host's other routes and fallbacks after the disabled-route guard.
app.Run();
```

Reuse the same captured startup flag for registration and mapping. The gate binds the `Mcp` section
to `McpConfig` once at composition time, because routes are decided before the service provider
exists. Missing `Mcp:Enabled` means disabled; an invalid boolean fails configuration binding.
Enabling it is restart-required.
The permission claim is synthetic: map it deliberately to the host's validated authorization
model, never trust a caller-supplied tool argument as proof of scope.

The disabled guard prevents a catch-all route from answering MCP requests. Enabled mode is for
native clients only: **every present Origin header**, including empty or `null`, is rejected.
For browser clients replace that rule with approved exact-origin validation, not wildcard CORS.
Host filtering, request budgets and safe telemetry remain host responsibilities.

## Expected Wire Contract and Validation

With approval, use a synthetic source and an isolated HTTP fixture; do not read production state:

| Case | Required observation |
| --- | --- |
| Disabled | `/mcp` returns 404, even with a host fallback |
| Discovery | Exactly `get_runtime_snapshot`; no DI service or cancellation token in input schema |
| Successful call | `structuredContent` matches the advertised output schema and contains only the three described fields |
| Source changes after startup | A later call reflects new counts; the facade uses the same running source |
| Source unavailable | A safe tool error with `IsError = true`, not a success with zero counts |
| Cancellation | The source receives cancellation; no successful fallback result |
| Missing/insufficient identity | 401/403 through the host's real auth boundary |
| Present Origin | 403 before source invocation |
| Unknown tool | SDK protocol error, not the known-tool application-error path |

The `McpException` message is intentionally public-safe. Do not append underlying exception text.
No manual JSON serialization or `CallToolResult` construction is necessary here: the SDK handles
the structured result and tool-error mapping. Follow the full
[protocol validation matrix](../references/validation.md) when integrating; compiling these files
or calling the facade directly does not establish HTTP interoperability or OAuth correctness.

## Deliberate Exclusions

History requires server-side row/time/text limits and caller-scope intersection; this constant-size
snapshot does not implement or stand in for those controls. Use the
[bounded-results reference](../references/results.md) before adding history.

Write tools belong in a separately authorized, off-by-default facade. A read-only annotation is
not enforcement; do not add a mutation to this class and rely on its name or this endpoint's read
permission. Follow [authorized actions](../references/authorized-actions.md) instead.
