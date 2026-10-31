# Shared Feature Host Wiring

These C# fragments demonstrate the inspected shared hosting contract on .NET 10. They require
compatible released versions of `CasCap.Common.Abstractions`, `CasCap.Common.Services` and
`CasCap.Common.Hosting.AspNetCore` in the consuming application's existing package configuration.
Verify availability/signatures before use; this is not a standalone compiled fixture.

## Register One Selected Worker

After the application has parsed and validated a nonempty set of supported feature names. Feature
names cross the configuration boundary, so they are `nameof()` constants rather than repeated literals:

```csharp
namespace Example.Constants;

public static class FeatureNames
{
    public const string CatalogApi = nameof(CatalogApi);
    public const string InventoryWorker = nameof(InventoryWorker);
}
```

```csharp
using CasCap.Common.Abstractions;
using CasCap.Common.Extensions;
using Example.Constants;
using Microsoft.Extensions.DependencyInjection;

IReadOnlySet<string> enabledFeatures =
    new HashSet<string>([FeatureNames.InventoryWorker], StringComparer.OrdinalIgnoreCase);

if (enabledFeatures.Contains(FeatureNames.InventoryWorker))
    builder.Services.AddSingleton<IBgFeature, InventoryFeature>();

builder.Services.AddFeatureFlagService(enabledFeatures);
builder.Services.AddControllers().AddFeatureGatedControllers(enabledFeatures);
```

`builder` is the application's existing `WebApplicationBuilder`. `InventoryFeature` is its own
implementation; no extra `AddHostedService<InventoryFeature>()` registration is needed or intended.
The shared dispatcher owns launching `IBgFeature.ExecuteAsync(CancellationToken)`.

The selection shown is deliberately concrete to explain the API. Production registration should
derive the set from validated, strongly-typed configuration, not hardcoded role selection. Add shared dependencies and the actual worker implementation before building the host.

## Gate a Controller in the Same Assembly

```csharp
using CasCap.Common.Abstractions;
using Example.Constants;
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("api/catalog")]
[FeatureController(FeatureNames.CatalogApi)]
public sealed class CatalogController : ControllerBase
{
    [HttpGet("status")]
    public ActionResult<string> GetStatus() => Ok("available");
}
```

The synthetic controller intentionally has no external dependencies. In the selected worker-only
profile it must be absent from routing and API discovery/OpenAPI, not activated and then rejected.
Add authentication/authorization according to the real API contract; this fragment demonstrates
discovery only.

For `[FeatureController(FeatureNames.CatalogApi, FeatureNames.InventoryWorker)]`, **either** enabled name exposes the
controller. Do not use this to describe an endpoint requiring both modules.

## Lifetime Contract to Verify

An `IBgFeature` exposes `FeatureName` and `Task ExecuteAsync(CancellationToken)`. A feature named
`IBgFeature.AlwaysEnabled` bypasses ordinary selection in the inspected .NET 8+ shared contract;
use that only for truly common work, not as a workaround for invalid role configuration.

- A daemon implementation propagates cancellation and awaits all owned work.
- A finite implementation must use the verified dispatcher shutdown contract, or run through a
  separate explicit finite mode rather than this daemon wiring.
- Every matching registration executes; duplicate registrations are not deduplicated by feature name.
- A dispatcher fault requests host shutdown. A nonzero process exit still needs verified
  host/entrypoint handling; `StopApplication` alone does not establish it.

Use host/route tests for the acceptance cases in the role-profile example, plus a process-level
test if an orchestrator relies on failure exit codes. No compilation or runtime result is claimed
by these fragments.
