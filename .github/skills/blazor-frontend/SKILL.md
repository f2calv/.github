---
name: blazor-frontend
description: 'Create, extend, audit or troubleshoot Blazor Web App frontends: render-mode choice, co-hosted WebAssembly client projects, component libraries, typed API clients, OIDC cookie authentication, antiforgery, multi-replica assets and Data Protection, and component or browser tests.'
---

# Blazor Frontend

Add or change a Blazor frontend with an explicit render-mode decision, a thin component layer over
authorized HTTP APIs and a deployment that survives several replicas. Verify current framework and
package behavior while implementing; do not rely on remembered template output.

## Authorities

- [Blazor instructions](../../instructions/dotnet.blazor.instructions.md) own component invariants.
- [C# instructions](../../instructions/dotnet.csharp.instructions.md) own types, DI, cancellation and
  logging. [Web API instructions](../../instructions/dotnet.webapi.instructions.md) and the
  [Web API skill](../dotnet-webapi/SKILL.md) own the controllers the frontend calls.
- [Configuration instructions](../../instructions/dotnet.configuration.instructions.md) own options
  and secret placement. [Testing instructions](../../instructions/dotnet.testing.instructions.md) own
  test approval and layout.
- [Container images](../container-images/SKILL.md) owns Dockerfiles that publish the host.

Keep application-specific choices, such as one application's render mode or tenant model, in that
repository's own instructions rather than in these shared files.

## Workflow

### 1. Establish the Context

Read the host bootstrap, middleware order, authentication schemes, authorization policies, API
controllers and contracts, solution files, Dockerfile and deployment chart before editing. Record
the routes the browser must call and which of them already serve machine callers.

### 2. Choose the Render Mode

| Mode | Use when | Costs |
| --- | --- | --- |
| Interactive WebAssembly | Replicas must stay interchangeable, or browser-owned state suits the app | Larger first download; every server operation is an explicit HTTP API |
| Interactive Server | Low-latency internal tools that may hold a live server circuit per user | Sticky circuits, reconnects and per-user server memory; a SignalR backplane does not move circuits |
| Interactive Auto | First paint must be fast and the team accepts both models | Inherits the Server circuit concerns and duplicates the data-access boundary |
| Static server rendering | Content pages and simple forms | No rich component interactivity |

Apply the mode globally on `Routes` and `HeadOutlet` unless pages deliberately differ. Disabling
prerendering (`new InteractiveWebAssemblyRenderMode(prerender: false)`) simplifies a first frontend:
components run only in the browser, so they never need server-side data paths or persisted state.

### 3. Scaffold From the Current Template

Generate a reference project in a temporary directory and copy its wiring rather than writing it
from memory, then delete the directory:

```powershell
$reference = Join-Path ([IO.Path]::GetTempPath()) 'blazor-reference'
dotnet new blazor -n Reference -o $reference --interactivity WebAssembly --all-interactive --empty
```

For a co-hosted WebAssembly frontend:

- Add a `Microsoft.NET.Sdk.BlazorWebAssembly` client project under `src/`, referenced by the host.
  Add it to every solution file the repository builds, including Release and container paths.
- The host references `Microsoft.AspNetCore.Components.WebAssembly.Server`, keeps `App.razor` and
  maps `MapStaticAssets()` and `MapRazorComponents<App>().AddInteractiveWebAssemblyRenderMode()`
  with `AddAdditionalAssemblies` for the client assembly.
- Copy template properties such as `BlazorDisableThrowNavigationException`, the router's
  `NotFoundPage` and `ResourcePreloader`, then reconcile them with the repository's central package
  management, analyzers and `GlobalUsings.cs` conventions.
- Keep existing API, health and protocol routes ahead of the component fallback, and confirm that an
  unknown `/api` path still returns a JSON 404 rather than the HTML shell.

### 4. Add the Component Library

Use one library. Check its current stable release and installation guide when adding it, then
register its services in the client, add its providers to the root layout and reference its assets
through `@Assets[...]` so fingerprinting applies. Self-host fonts or use the system font stack
instead of a third-party font CDN, which leaks visitor addresses and complicates a content security
policy. For MudBlazor follow the [installation guide](https://mudblazor.com/getting-started/installation).

### 5. Build the API Boundary

- Serve browser endpoints from the same origin, under a route prefix separate from machine APIs.
- Keep controllers thin and reuse application services. Return allowlisted DTOs designed for the
  screen; never serialize configuration records, entities or anything that can carry credentials.
- Write one typed client service per API area in the client project, returning typed outcomes the
  components can render.
- Treat route identifiers such as a tenant key as requested targets. Authorize every one on the
  server against the authenticated user.

### 6. Authenticate With a Host-Owned Cookie

- Run OIDC authorization code with PKCE on the server with a dedicated web registration, and sign the
  browser in with a named Secure, HttpOnly, SameSite cookie. Do not save tokens unless the host must
  call a downstream API on the user's behalf.
- Keep machine bearer-token policies separate. Select the cookie scheme explicitly on browser
  endpoints instead of changing the default scheme the machine APIs rely on.
- Make browser API endpoints return 401 and 403 instead of redirecting to the identity provider; only
  navigational login and logout endpoints redirect.
- Flow authentication state to WebAssembly with `AddAuthenticationStateSerialization` on the host and
  `AddAuthenticationStateDeserialization` in the client, and authorize again on every API call.
- Enforce antiforgery on every cookie-authenticated mutation, including logout. With a co-hosted
  WebAssembly client, issue a request token from a same-origin endpoint and send it in a header.
- Derive audit actors from the validated principal, never from a request body.

### 7. Prepare for Several Replicas

- Persist the Data Protection key ring in shared durable storage with a fixed application name, and
  protect keys at rest. Pod-local keys or an evictable cache break cookies and antiforgery tokens on
  the next replica.
- Validate exact HTTPS callback URLs and configure forwarded headers only for trusted proxies.
- During a rolling release an old page can request assets the new replica no longer serves.
  Fingerprinted assets avoid stale caches but not that gap; verify a reload recovers, and keep the
  previous release's assets available when it does not.
- Do not require session affinity. Test two replicas, a pod replacement mid-session and a mixed-version
  reload before declaring the frontend highly available.

### 8. Test

Ask before running tests. Cover API authorization, cross-tenant access, antiforgery, 401/403 and
validation with host tests; render-state and form logic with a small bUnit suite; and one or two
end-to-end browser journeys with Playwright. Keep credentials out of tests.

### 9. Validate and Document

- Build and publish through every supported path and confirm the published output contains the
  client's `_framework` assets.
- Inspect downloaded assemblies, `wwwroot` configuration, API payloads and browser storage for
  secrets, tokens and private identifiers.
- Check keyboard operation, focus, labels, contrast and narrow viewports.
- Document how the host, the downloaded client and the APIs fit together for maintainers new to
  Blazor.
