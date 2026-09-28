---
name: dotnet-mcp
description: 'Create, modify, modernize, or audit .NET MCP server tools, protocol prompts, registration, options, DTOs and tests, including Mcp-named files and Mcp folders. Covers read-only Streamable HTTP, live state, bounded history, privacy and protocol validation.'
argument-hint: 'mode={create|update|audit} [scope=application]'
user-invocable: true
---

# .NET HTTP MCP

Expose a deliberately small, read-only-by-default application surface through the official MCP C# SDK.
Reuse the application's running services and persistence; do not build a second application,
an arbitrary database console, or an unrestricted remote administration endpoint.

## Modes and prerequisites

| Mode | Outcome |
| --- | --- |
| `create` | Add an opt-in HTTP endpoint, explicit query tools, configuration, documentation, and proposed validation |
| `update` | Modernize an existing endpoint against the selected stable SDK and preserve intended contracts |
| `audit` | Make no edits; report evidence, risks, missing coverage, and a bounded remediation plan |

1. Read the target repository instructions, status, existing MCP implementation, configuration,
   service registrations, role selection, persistence code, and relevant tests before editing.
   Preserve unrelated changes. Work only in the requested repository scope.
2. Read [MCP naming and descriptions](../../instructions/dotnet.mcp.instructions.md), the sole
   authority for tool names and `[Description]` conventions. Do not copy those rules into this skill.
   Also apply the shared [.NET](../../instructions/dotnet.instructions.md),
   [C#](../../instructions/dotnet.csharp.instructions.md),
   [configuration](../../instructions/dotnet.configuration.instructions.md),
   [NuGet](../../instructions/dotnet.nuget.instructions.md), and
   [testing](../../instructions/dotnet.testing.instructions.md) instructions as applicable.
3. Agree a read-only first scope: typically runtime snapshots and narrowly scoped persisted history.
   Sending messages, changing settings, retries, queue consumption, workflow execution, arbitrary
   SQL, shell commands, and generic file access are out of scope unless separately authorized.
4. Do not run tests or make live service/data reads without explicit approval. An MCP connection
   can disclose data to the client/model even when every tool is read-only. Use synthetic local
   fixtures for approved validation; never discover capabilities by reading production history.

## Align file scope

Use the [instruction file's naming convention](../../instructions/dotnet.mcp.instructions.md#naming)
as the authority for MCP-specific files. Before narrowing coverage or reorganizing an existing
implementation:

1. Inventory tool/prompt attributes, registration helpers, options, MCP-only output types and tests by
   content, not only filename. Classify shared application components separately.
2. Move tracked files with `git mv` before editing their types or references. Update DI, tests,
   XML references and documentation together. Preserve exposed tool names, parameter/property names,
   namespaces where appropriate, and runtime behavior; this is file targeting, not API redesign.
3. Check that every MCP-specific C# file matches `**/*Mcp*.cs` or `**/Mcp/**/*.cs`, using case-sensitive
   examples. Confirm unrelated application files do not match; keep shared services and composition
   roots outside the pattern rather than widening it to all C#.
4. Distinguish static glob coverage from actual editor activation. Check VS Code customization
   diagnostics in the intended workspace/profile before claiming automatic application works.
   Report that check as pending if the editor cannot expose it.

Skill selection remains task-driven through its description, including work on files not yet
following the convention. The instruction `applyTo` glob does not itself invoke the skill.

## Refresh the SDK evidence

Before implementation or modernization:

* Inspect installed and centrally managed package versions, target frameworks, SDK constraints,
  and the actual clients/protocol revisions to support.
* Resolve the latest stable `ModelContextProtocol.AspNetCore` from configured NuGet sources;
  inspect its dependency graph and release notes. Select and pin a compatible stable version in
  the application's normal package authority. Do not leave floating versions or prescribe a
  permanently fixed package version in this workflow.
* `ModelContextProtocol.AspNetCore` is the HTTP package and brings the hosting/core layers
  transitively. Avoid redundant references unless the project directly needs them.
* Use documentation matching the selected major and, where behavior matters, source at its release
  tag. The documentation root can resolve to an older major: the
  [v2 getting-started guide](https://csharp.sdk.modelcontextprotocol.io/v2/concepts/getting-started.html)
  and [v2 tool API](https://csharp.sdk.modelcontextprotocol.io/v2/api/ModelContextProtocol.Server.McpServerToolAttribute.html)
  are explicit major-version links, not a promise about the latest installed package.
* Recheck transport options, tool activation, injected parameters, structured output, exception
  handling, cancellation, and client configuration rather than porting examples from memory.
  Record the version and sources actually checked in the implementation handoff.
* The checked [tool attribute API](https://csharp.sdk.modelcontextprotocol.io/v2/api/ModelContextProtocol.Server.McpServerToolAttribute.html)
  has no `Description` property. Apply the separate description attribute required by the linked
  naming/description conventions; do not copy an unsupported named argument into tool declarations.

The patterns below were checked against the v2 documentation and `v2.2.0` source. They are an
implementation starting point, not evidence that a consuming application has compiled or passed
tests. Refresh them when a later supported SDK changes the contract.

## Design the boundary

Write down the intended tool inventory, each tool's data source and lifetime, required host role,
authorization scope, output fields, bounds, and privacy behavior before changing registrations.

### Feature and role gating

* Default MCP to disabled. Gate both `AddMcpServer` registration and `MapMcp` route mapping on the
  same validated startup configuration; hiding tools alone does not disable the endpoint.
* Validate each role's dependencies before startup: history needs the existing store and runtime
  queries need initialized live services, in-process or through a designed remote query boundary.
  Reject invalid combinations with actionable, non-sensitive errors, or explicitly register and
  document only the supported subset. Never substitute dummy services or misleading zero counts.
* Give sensitive history its own disabled-by-default feature gate. When it is off, omit the history
  tool from registration and discovery, and reject direct calls to its name; do not merely return
  empty results from an advertised tool.
* Treat startup gating as restart-required unless runtime changes are explicitly implemented.
  Do not imply an options reload unmaps an existing route. Disabled means requests to the MCP path
  return 404, including in applications with catch-all/fallback endpoints.

### Transport and explicit discovery

For a simple query surface, use Streamable HTTP and explicitly select
`HttpServerSessionMode.Stateless`. It avoids session affinity and session-only state. Do not enable
legacy SSE, invent a JSON-RPC controller, or use obsolete options copied from an older SDK.
Applications needing notifications, client requests, or session state need a separate transport
decision checked against their actual protocol revision.

This registration excerpt assumes `builder` exists, configuration has been validated, and the
application supplies the named query facade and authorization policy:

```csharp
using ModelContextProtocol.AspNetCore;

var mcpEnabled = builder.Configuration.GetValue<bool>("Mcp:Enabled");

if (mcpEnabled)
{
    builder.Services.AddMcpServer()
        .WithHttpTransport(options =>
            options.SessionMode = HttpServerSessionMode.Stateless)
        .WithTools<RuntimeQueryService>();
}

var app = builder.Build();

// Configure authentication, authorization, and the MCP Origin guard before mapping endpoints.
if (mcpEnabled)
{
    app.MapMcp("/mcp").RequireAuthorization("McpRead");
}
```

* Add each approved tool type with `WithTools<T>()`. Do not use `WithToolsFromAssembly()` by
  accident: it can expose unrelated annotated types. For a mixed read/write class, introduce a
  dedicated read-only facade or explicitly construct the approved method inventory.
* Understand activation: in the checked SDK, `WithTools<T>()` creates an instance target per
  invocation with `ActivatorUtilities.CreateInstance`; it does not automatically reuse a registered
  singleton of that tool type. Inject the real running service into a thin facade. Do not expose a
  second, unstarted hosted-service instance as if it represented the running application.
* Register dependencies before tool discovery/schema creation. Constructor DI is suitable for the
  facade; supported method-injected services and `CancellationToken` are not model arguments.
  Assert their absence in `inputSchema`.
* Preserve lifetimes. Do not capture a scoped `DbContext` in a singleton, create a second root
  provider, or keep per-call state in a shared tool target. Reuse the application's existing
  scoped store or context factory.

### Explicitly authorized actions

Write capabilities are out of scope by default. When the user separately authorizes one, load
[authorized actions](references/authorized-actions.md) before designing it: keep it in its own
off-by-default facade, reuse the domain service and its validation, and never replay an
outcome-uncertain operation automatically.

## Shape useful, bounded results

Load [bounded results](references/results.md) when designing any tool output. Its invariants:

* Runtime snapshots read the live service at call time and return detached DTOs; counts and flags are
  not health checks, and configuration, credentials and identifiers are never returned.
* Persisted history queries the application's own store, requires an explicit channel scope
  intersected with the caller's authorization, and bounds rows, time window, text and duration
  server-side before materializing. Text disclosure is off by default and treated as untrusted data.
* Query tools set `UseStructuredContent = true` and accurate read-only annotations, keep empty,
  unavailable and failed results distinguishable, propagate cancellation, and never log arguments,
  results, history text or identifiers.

## Secure HTTP exposure

Choose and document one deployment boundary — an isolated loopback listener or a remote HTTPS service
with MCP-compatible OAuth — before enabling the route. The checked SDK does not validate `Origin`;
add an endpoint-scoped guard that rejects invalid origins with 403 before tool dispatch, and never
solve connection failures with wildcard CORS, disabled authentication, public ingress or `0.0.0.0`
binding. Load [HTTP exposure and client configuration](references/http-security.md) for the controls,
the Origin guard pattern and VS Code client configuration.

## Validate the actual boundary

Propose the smallest fixture-backed validation and obtain approval before execution. Build success,
direct method calls, reflection tests or an HTTP GET are not MCP interoperability proof. Load
[protocol validation](references/validation.md) for the required initialization, discovery,
invocation, gating, scope-isolation, privacy, failure and HTTP-control assertions.

## Handoff and maintenance

Report changed files, SDK/source versions inspected, tool inventory, default feature state, role
dependencies, deployment boundary, and text-disclosure behavior. Separate static inspection,
compilation, protocol tests, and approved live-client observations; list checks not run.
Keep implementation marked ongoing until the promised application evidence exists. Never turn an
example or another session's unverified claim into a passed test or completed integration.

Update the consuming application's configuration/developer documentation without private identities
in public examples. Feed durable SDK/workflow corrections back into this skill and naming/description
corrections into their linked authority only; do not create duplicate convention lists.

## API evidence

* [v2 transport options](https://csharp.sdk.modelcontextprotocol.io/v2/api/ModelContextProtocol.AspNetCore.HttpServerTransportOptions.html)
  and [stateless behavior](https://csharp.sdk.modelcontextprotocol.io/v2/concepts/stateless/stateless.html)
* [v2 tools: structured content and exception handling](https://csharp.sdk.modelcontextprotocol.io/v2/concepts/tools/tools.html)
* [v2 tool registration APIs](https://csharp.sdk.modelcontextprotocol.io/v2/api/Microsoft.Extensions.DependencyInjection.McpServerBuilderExtensions.html)
  and [v2.2.0 activation source](https://github.com/modelcontextprotocol/csharp-sdk/blob/v2.2.0/src/ModelContextProtocol/McpServerBuilderExtensions.cs)
* [v2.2.0 transport source](https://github.com/modelcontextprotocol/csharp-sdk/blob/v2.2.0/src/ModelContextProtocol.AspNetCore/HttpServerTransportOptions.cs)
* [Streamable HTTP Origin requirements](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#security-warning)
  and [v2 HTTP hosting guidance](https://csharp.sdk.modelcontextprotocol.io/v2/concepts/transports/transports.html)
