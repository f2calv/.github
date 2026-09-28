# HTTP Exposure and Client Configuration

Load before enabling the MCP route beyond an isolated local listener, or when configuring an MCP client.

## Secure HTTP exposure

Choose and document one deployment boundary before enabling the route:

| Boundary | Required controls |
| --- | --- |
| Local development or operator port-forward | Loopback-only local listener/forward, trusted local users, no public ingress or shared unauthenticated network exposure |
| Remote/shared service | HTTPS, MCP-compatible OAuth authorization, least-privilege policies, per-call channel authorization, and request/resource limits |

* For remote service access follow the
  [MCP authorization specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization):
  protected resource metadata/discovery, appropriate `401` challenges, issuer/audience/signature/
  expiry validation, and scoped access tokens. Do not pass through unrelated upstream tokens.
  Adapt the application's existing identity stack rather than inventing an OAuth server.
* The registration example deliberately requires authorization. Omitting it is only acceptable for
  an explicitly accepted isolated local boundary; a loopback port-forward on the client does not
  secure an otherwise exposed server-side listener. Keep that listener private and access-controlled.
* Validate `Origin` for every MCP request carrying it; reject invalid, malformed, `null`, or
  unapproved origins with 403 before tool dispatch. For non-browser clients a missing Origin may
  be accepted under the chosen authentication/network boundary. Use an exact origin allowlist.
* Do not assume `MapMcp`, `AllowedHosts`, or a CORS policy performs that Origin rejection.
  The checked SDK endpoint does not implement Origin validation automatically. Add an
  endpoint-scoped guard, and recheck the selected SDK/host behavior when upgrading. For a
  native-editor-only endpoint with no browser use case, reject every present `Origin` header
  with 403 (including empty or `null` values). A route-group endpoint filter composed as
  `MapGroup("/mcp").AddEndpointFilter(...).MapMcp()` is a verified integration pattern; it must
  short-circuit before calling the next handler when the header is present. For approved browser
  access, use exact-origin validation instead. CORS alone can withhold browser response access
  without preventing request execution.
* Restrict allowed Host names and trust forwarded headers only from known proxies. If browser access
  is needed, add a separate restrictive CORS policy. Never solve connection failures with wildcard
  CORS, disabled authentication, a public unauthenticated ingress, or `0.0.0.0` local binding.
* Enforce request sizes, concurrency, timeouts, and rate limits appropriate to the host. Neither
  stateless mode nor read-only tools remove denial-of-service or data-exfiltration risks.

## Configure the client

Follow the shared [MCP configuration rules](../../../instructions/mcp.configuration.instructions.md)
for ownership and secret handling. Use the current
[VS Code MCP configuration reference](https://code.visualstudio.com/docs/agents/reference/mcp-configuration);
the VS Code format uses `servers`, not the portable format's `mcpServers`.

For an explicitly isolated local listener or loopback port-forward:

```json
{
  "servers": {
    "example-query": {
      "type": "http",
      "url": "http://localhost:3001/mcp"
    }
  }
}
```

The port is synthetic; use the actual approved local forward. Do not add `/sse`. For remote access,
use the HTTPS MCP endpoint and the configured OAuth flow; supply an `oauth.clientId` only when the
client registration requires it. Do not publish real endpoints or credentials.
VS Code's Agent Host does not forward definitions requiring interactive `${input:...}` variables;
choose a supported configuration path for that client rather than assuming portability.

With approval, restart the server connection and refresh its tool inventory after schema changes.
Inspect **MCP: List Servers** and **Show Output** without enabling payload logging. Client-side
tool enablement is not a server access-control mechanism.
