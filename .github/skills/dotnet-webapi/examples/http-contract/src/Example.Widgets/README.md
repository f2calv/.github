# Example.Widgets

HTTP-neutral synthetic DTOs and the [WidgetService](Services/WidgetService.cs) used by both
comparison hosts. The service validates names, detects duplicates, projects widget DTOs and opens
fixed synthetic content; it returns domain outcomes, nullable resources and streams, never HTTP results.

The hosts register one singleton instance. Its locked in-memory store starts with widget 1 and is
discarded on process exit. This intentionally provides no persistence, credentials or configuration.
There are no NuGet dependencies, framework references or project references.

See the [comparison commands and limits](../../README.md) for build and HTTP test usage.
