---
description: 'Blazor component conventions for Razor markup, code-behind, isolated styles, browser-public code, lifecycle, forms, errors, accessibility and the HTTP boundary.'
applyTo: '**/*.razor,**/*.razor.cs,**/*.razor.css,**/*.razor.js'
---

# Blazor Components

Use the [blazor-frontend skill](../skills/blazor-frontend/SKILL.md) to choose render modes, add a
client project, wire authentication or validate a multi-replica deployment. This file owns component
invariants. C#, Web API, configuration and testing rules stay in their own instruction files.

## Code Placement

- Keep markup in `.razor` and non-trivial logic in a partial `.razor.cs` code-behind. A component
  whose `@code` block only declares parameters or forwards one event may keep it inline.
- Inject dependencies through the code-behind primary constructor, following the C# naming rules.
  Use `@inject` only in markup-only components.
- When the code-behind derives from a shared component base class, also declare it with `@inherits`
  in the markup; the generated partial otherwise declares `ComponentBase` and the two conflict.
- Share cross-cutting component behaviour, such as owning cancellation, through a small abstract
  base component rather than repeating it in every page.
- Put component styles in an isolated `.razor.css` file. Avoid inline `style` attributes except for
  values computed at runtime; use the component library's own parameters for its styling.
- Use one component library per application. Do not mix its primitives with a second library's.
- Split a component once it owns more than one screen concern, such as a list and an editor dialog.

## Browser-Public Code

- Treat every assembly, static asset and `wwwroot` configuration file downloaded by WebAssembly as
  public. Never place secrets, private hostnames, connection strings, internal identifiers or
  server-only feature flags in a client project.
- A client project references only contracts, the browser framework and UI packages. Never reference
  EF Core, provider SDKs, server configuration types or execution implementations from it.
- Never store access tokens, refresh tokens or identity documents in `localStorage`,
  `sessionStorage`, IndexedDB or component state. Rely on the host's HttpOnly session cookie.
- Duplicate server validation in the browser only for user experience. The server remains the
  authority; display its validation result rather than assuming the client check was sufficient.

## Lifecycle, Parameters and Rendering

- Load data in `OnInitializedAsync`, or in `OnParametersSetAsync` when route or query parameters
  select the data. Compare the previous values before reloading in `OnParametersSetAsync`.
- Never assign to a `[Parameter]` property from inside its component. Copy it into private state.
- Never call JavaScript interop before `OnAfterRenderAsync(firstRender: true)`.
- Return `Task` from event handlers; never write `async void`. Await the work rather than firing and
  forgetting it.
- Call `StateHasChanged` only when state changes outside a Blazor event or lifecycle callback, for
  example from a timer or service event, and marshal it with `InvokeAsync`.
- Give every rendered collection item a stable domain `@key`, not its loop index.
- Prefer route and query parameters (`[SupplyParameterFromQuery]`) for selections and searches that
  should survive refresh, sharing and navigation. Avoid a global state container for page state.

## Cancellation and Disposal

- Own a `CancellationTokenSource` per component that issues HTTP calls. Pass its token to every call,
  cancel it when parameters select different data, and cancel and dispose it in `Dispose` or
  `DisposeAsync`.
- Treat cancellation caused by navigation or disposal as normal; never show it as an error.
- Unsubscribe from service events and dispose `DotNetObjectReference` and JavaScript module
  references in `DisposeAsync`.

## HTTP Boundary

- Components call a typed API client service, never `HttpClient` directly, and never build URLs
  inline. Keep route templates in a shared constants class.
- The API client maps HTTP outcomes to typed results: success, validation problem, unauthorized,
  forbidden, not found, conflict and unavailable. Components render each case explicitly.
- Never retry a mutating request automatically after an unknown outcome.

## Forms and Unsaved Work

- Use `EditForm` with an explicit `EditContext` and `DataAnnotationsValidator`. Map server
  `ValidationProblemDetails` into a `ValidationMessageStore` so field errors appear beside fields.
- Disable the submit action while a request is in flight, and keep entered values after an error.
- Warn before navigation away from a dirty form with `NavigationLock`, including
  `ConfirmExternalNavigation` for browser unloads.
- Require explicit confirmation, and a reason where the domain records one, for destructive or
  production-affecting actions.

## Page States

- Render distinct loading, empty, error, forbidden, not-found, conflict and unavailable states. Never
  leave a blank page or a permanent spinner after a failure.
- Show user-safe error text. Log diagnostic detail with `ILogger`, which in WebAssembly writes to the
  browser console, and never log tokens or personal data.

## Accessibility

- Give every input a visible label, and every icon-only button an accessible name.
- Keep `FocusOnNavigate` in the router, use one `h1` per page and set a `PageTitle`.
- Do not convey status by colour alone; pair it with text or an icon that has a label.
- Ensure dialogs trap and restore focus and close with Escape. Check keyboard-only operation and
  narrow viewports for every new screen.
