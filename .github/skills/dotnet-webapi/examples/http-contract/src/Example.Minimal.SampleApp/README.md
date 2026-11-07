# Example.Minimal.SampleApp

The Minimal API comparison host. [WidgetEndpoints](WidgetEndpoints.cs) registers one explicit
feature route group with statically visible handlers, concrete result unions and one shared-service
call per handler. No endpoint discovery framework or assembly scanning is used.

[AppJsonSerializerContext](AppJsonSerializerContext.cs) provides generated metadata for the request,
widget and problem bodies. Request-delegate generation is enabled; JSON reflection fallback is
disabled. The singleton service is registered only when its routes are mapped.

The host references `Example.Widgets` and the ASP.NET Core shared framework. Its AOT compiler is
resolved by the pinned SDK; there is no endpoint-framework package dependency. It has no
authentication or private configuration; use loopback only.

See the [comparison commands, native prerequisites and verification limits](../../README.md).
Enabling `PublishAot` does not establish native compatibility: the recorded publication attempt
stopped before linking because the platform linker was unavailable.
