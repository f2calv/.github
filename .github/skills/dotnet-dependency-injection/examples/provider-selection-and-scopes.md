# Selected Provider, Shared Broker, Scoped Jobs

A synthetic notification host selects one transport at startup. Producers and a hosted dispatcher
share a non-disposable in-memory broker. Each queued operation gets a fresh scoped job service.
These registration fragments are illustrative, not a compiled host.

## Select Without Constructing Inactive Integrations

After validating strongly typed configuration, use an explicit allowed mapping:

```csharp
services.AddSingleton<IMessageGateway>(provider =>
    provider.GetRequiredService<IOptions<TransportOptions>>().Value.Provider switch
    {
        TransportNames.Http => ActivatorUtilities.CreateInstance<HttpMessageGateway>(provider),
        TransportNames.Local => ActivatorUtilities.CreateInstance<LocalMessageGateway>(provider),
        _ => throw new InvalidOperationException("Unsupported transport selection.")
    });
```

`IMessageGateway`, options, constants and implementations are synthetic application types.
The fragment needs `Microsoft.Extensions.DependencyInjection` and `Microsoft.Extensions.Options`.
The HTTP implementation is a singleton-safe wrapper using `IHttpClientFactory` per operation,
not a transient typed client captured forever. There is one owning gateway registration.

Validate the selected transport's options at startup and explicitly resolve the selected factory
in a controlled validation path. `ValidateOnBuild` alone will not run this factory. A documented
local mode should not require HTTP credentials; invalid names must not fall back to local mode.
Provider selection is startup-only in this example.

## Share State Without Duplicate Owners

```csharp
services.AddSingleton<JobBroker>();
services.AddSingleton<IJobWriter>(provider => provider.GetRequiredService<JobBroker>());
services.AddSingleton<IJobReader>(provider => provider.GetRequiredService<JobBroker>());
services.AddScoped<JobService>();
services.AddHostedService<DispatchBgService>();
```

The broker is explicitly **not** `IDisposable` or `IAsyncDisposable`. Its dispatcher owns completion
and shutdown protocol, not container disposal of aliased resources. The dispatcher injects the
reader and `IServiceScopeFactory`; producers inject the writer. Do not also register the dispatcher
as another hosted instance. A disposable implementation needs a revised ownership design.

The dispatcher creates an async scope per job as shown in the lifetime reference. Neither the
broker nor singleton gateway captures `JobService` or its EF context.

## Acceptance Cases

| Case | Expected result |
| --- | --- |
| Supported provider selected | Only that gateway is constructed; constructor dependencies resolve |
| Unknown provider | Startup validation fails without echoing sensitive configuration |
| Producer and dispatcher resolve broker interfaces | Both reference the same broker instance |
| Two jobs run concurrently | Different scopes/context instances; broker remains thread-safe |
| Job fails or is cancelled | Scope is asynchronously disposed after awaited work finishes |
| Gateway implements async disposal | Container shutdown disposes its single owning registration |
| Configuration changes after startup | No claim that the constructed gateway automatically changes |
| Test provider substituted | Real HTTP/database resources are not opened |

Use existing isolated tests with authorization. These acceptance cases are requirements, not
reported execution results.
