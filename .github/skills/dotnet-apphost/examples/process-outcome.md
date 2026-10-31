# Process Outcome Example

Use one process outcome shared by the AppHost and background supervisor. Graceful shutdown returns
zero. Startup, direct-operation and fatal background failures return one after cleanup and logging
flush.

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddStandardConfiguration(
    builder.Environment.EnvironmentName,
    typeof(Program).Assembly);
builder.Services.AddApplicationHostLifecycle(builder.Configuration);
builder.Services.AddFeatureFlagService(enabledFeatures);

try
{
    await using var app = builder.Build();
    var exitState = app.Services.GetApplicationExitState();
    await app.RunAsync();
    return exitState.ExitCode;
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

Resolve `ApplicationExitState` before `RunAsync`: host execution can dispose the service provider
before returning. The feature supervisor marks the retained state before requesting
`StopApplication` and rethrowing. .NET logs the unhandled `BackgroundService` exception and performs
normal host shutdown; the AppHost reads the retained failure result afterward.

Background services outside that supervisor must either use an equivalent owning supervisor or mark
the same state before requesting shutdown. `BackgroundServiceExceptionBehavior.StopHost` alone does
not record a process failure.

Do not use `Environment.Exit(1)` for ordinary host failures: it bypasses normal shutdown, disposal
and logging/telemetry flush. Do not rely on `StopApplication` or
`BackgroundServiceExceptionBehavior.StopHost` alone, because graceful host completion does not
establish a nonzero process result.

For finite modes such as `--migrate`, return zero only after the operation and cleanup complete.
Catch and log unexpected failures at the same process boundary and return one.

## Process-Level Validation

Build a credential-free fixture executable with synthetic modes, then launch its built DLL through
`dotnet` from the test process. Assert the real child `ExitCode`, not only the in-process state:

| Fixture mode | Expected |
| --- | ---: |
| Fatal supervised daemon feature | `1` |
| Requested graceful shutdown | `0` |
| Finite migration success | `0` |
| Finite migration failure | `1` |

Redirect stdout/stderr, use a bounded timeout, and kill only the owned child process tree after a
test timeout. The fixture must not load credentials, contact services or apply a real migration.
