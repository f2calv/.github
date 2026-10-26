# Lifetimes, Factories and Ownership

## Registration Is Not the Effective Graph

With the built-in container, resolving one service normally uses the last registration; resolving
`IEnumerable<T>` returns all matching registrations in order. Repeating registration can therefore
duplicate workers or side effects even if single-service resolution looks correct. Inspect shared
extensions, `TryAdd`/`TryAddEnumerable`, scans and test overrides together.

Do not call `BuildServiceProvider` during registration to fetch dependencies. It creates a separate
ownership graph, can duplicate singletons and may retain objects past their intended lifetime.
Use registration factory overloads or the host's normal configuration pipeline.

Enable the existing host's scope/build validation in appropriate validation environments.
`ValidateOnBuild` does not execute arbitrary factories or validate every open generic construction;
explicitly resolve supported factory/key branches in isolated tests.

## Operation Scopes

A long-lived worker should inject `IServiceScopeFactory`, create an async scope per unit of work,
resolve that operation's service and await it before disposing the scope:

```csharp
await using var scope = serviceScopeFactory.CreateAsyncScope();
var jobSvc = scope.ServiceProvider.GetRequiredService<JobService>();
await jobSvc.ExecuteAsync(stoppingToken);
```

This is a fragment inside a worker method, with application `JobService` and injected dependencies.
Use the repository's namespaces and documentation conventions when adapting it.
Parallel jobs need independent scopes and contexts. Do not return a scoped service, open stream or
deferred query from a scope that has already ended.

## Provider and Strategy Selection

| Need | Prefer | Guardrail |
| --- | --- | --- |
| One configured implementation for the host lifetime | Explicit registration selected at composition | Validate selection before work; no arbitrary type names from configuration |
| A small known set selected per operation | Existing keyed services or a narrow typed factory | Validate unknown keys and operation lifetime; avoid leaking the root provider |
| New independent scoped operation | Async scope or existing specialized factory | Caller awaits work and releases ownership deterministically |
| One fixed implementation with no substitution seam | Direct concrete registration | Do not add an interface or abstract factory without a real consumer |

`ActivatorUtilities.CreateInstance` resolves constructor dependencies from the supplied provider;
it does not make that provider own every instance created manually. An instance returned from a
normal DI registration factory is container-owned; one manually created outside that registration
needs an explicit caller-owned lifetime. Do not dispose injected dependencies owned by the container.

Changing configuration does not replace an already constructed singleton. Either document
startup-only selection or implement a deliberate swap protocol covering concurrent use, in-flight
operations and disposal. `IOptionsMonitor` alone does not provide that protocol.

## Aliases and Disposal

Registering `Broker` and `IBroker` separately by implementation type creates separate instances.
For a **non-disposable** shared coordinator, interface aliases can resolve the concrete registration.
Verify reference identity for every consumer, including hosted wrappers.

Do not copy that alias pattern indiscriminately for disposable types: multiple factory registrations
returning the same disposable object can cause multiple disposal captures in the built-in container.
Prefer one owning registration plus non-owning facades/wrappers, or an explicitly externally owned
instance whose owner disposes it exactly once after consumers stop. Avoid depending on accidental
idempotent disposal to make the graph safe.

Instances supplied through `AddSingleton(instance)` are externally owned with the built-in
container. A manually created instance registered this way must have a real shutdown owner.
Use async disposal when required and preserve the original failure if cleanup also fails according
to the application's error policy.

## Further Reading

- [Service lifetimes](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/service-lifetimes)
- [Scoped services in a BackgroundService](https://learn.microsoft.com/en-us/dotnet/core/extensions/scoped-service)
- [Keyed service registration](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/overview#keyed-services)

Check API availability against the consumer's pinned SDK/packages before using a newer facility.
