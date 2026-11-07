# Example.Controllers.SampleApp

The managed MVC comparison host. [WidgetsController](Controllers/WidgetsController.cs) binds
requests, calls the shared service once per action and maps outcomes to concrete typed HTTP results.
`ApiController` supplies the MVC binding pipeline; the checked name validation belongs to the service.

This host references `Example.Widgets` and the ASP.NET Core shared framework, with no direct NuGet
dependencies. It does not enable Native AOT. Feature disabling removes both controller registration
and mapping. There is no authentication or private configuration; use loopback only.

See the [comparison commands and limits](../../README.md) for build, launch and HTTP test usage.
