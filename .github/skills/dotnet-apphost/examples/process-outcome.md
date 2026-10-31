# Process Outcome Example

Use one process outcome shared by the AppHost and background supervisor. Graceful shutdown returns
zero. Startup, direct-operation and fatal background failures return one after cleanup and logging
flush.

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationExitState();
builder.Services.AddFeatureFlagService(enabledFeatures);

try
{
    await using var app = builder.Build();
    await app.RunAsync();
    return app.Services.GetApplicationExitCode();
}
catch (Exception exception)
    when (exception is not OperationCanceledException and not TaskCanceledException)
{
    Log.Fatal(exception, "{AppName} terminated unexpectedly",
        AppDomain.CurrentDomain.FriendlyName);
    return 1;
}
finally
{
    await Log.CloseAndFlushAsync();
}
```

The feature supervisor marks `ApplicationExitState` before requesting `StopApplication` and
rethrowing. .NET logs the unhandled `BackgroundService` exception and performs normal host shutdown;
the AppHost reads the retained failure result after `RunAsync` completes.

Background services outside that supervisor must either use an equivalent owning supervisor or mark
the same state before requesting shutdown. `BackgroundServiceExceptionBehavior.StopHost` alone does
not record a process failure.

Do not use `Environment.Exit(1)` for ordinary host failures: it bypasses normal shutdown, disposal
and logging/telemetry flush. Do not rely on `StopApplication` or
`BackgroundServiceExceptionBehavior.StopHost` alone, because graceful host completion does not
establish a nonzero process result.

For finite modes such as `--migrate`, return zero only after the operation and cleanup complete.
Catch and log unexpected failures at the same process boundary and return one.
