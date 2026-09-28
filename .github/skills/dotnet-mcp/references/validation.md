# Protocol Validation

Load when proposing or running fixture-backed validation of an MCP endpoint.

Propose the smallest fixture-backed validation and obtain approval before execution. Build success,
direct method calls, reflection tests, or a successful HTTP GET are not MCP interoperability proof.
Use the repository's existing test platform and an in-process HTTP host or isolated loopback fixture.
Prevent the fixture host from starting real workers or contacting external services.

| Check | Required assertion |
| --- | --- |
| Initialization and revision | Exercise real `initialize` and initialized notification for a handshake-based client (for example `2025-11-25`); assert negotiated capabilities/version. Also exercise the selected current client's path: `2026-07-28` removes the wire initialize handshake, so do not mistake SDK client construction for proof that it occurred |
| Discovery | `tools/list` exposes exactly the approved names, descriptions, input/output schemas, and read-only annotations; DI services and cancellation are absent from model arguments |
| Invocation | `tools/call` succeeds over HTTP and its actual `structuredContent` validates against advertised `outputSchema`, including presence and value of promised explicit-null fields; do not pass by parsing only text content |
| Disabled/unsupported roles | Disabled endpoint returns 404; each supported role exposes only resolvable tools; invalid enabled dependency combinations fail configuration as designed |
| Live state | Change the injected running service's fixture state after host startup; the next call reflects it, with no duplicate hosted-service instance |
| History bounds | Zero/negative/excessive limits, invalid time windows, deterministic ordering, cancellation, response truncation, and total text budgets are enforced |
| Scope isolation | Seed at least two channels/tenants; authorized scope cannot read the other, including through cursors, errors, counts, or omitted filters |
| Privacy | Disabled history is absent from discovery and cannot be called; metadata-only calls never select/return text; operator and organizational-policy gates control disclosure; permitted text is SQL-bounded with a truncation indicator; forbidden identifiers, secrets, and payload logs are absent; hostile history remains data |
| Failure behavior | Empty history differs from store failure; safe tool errors, protocol errors, and cancellation remain distinguishable without exception-detail leakage |
| HTTP controls | Invalid Origin gets 403 before invocation; native-editor-only endpoints reject every present Origin header; allowed/no-Origin cases match policy; Host filtering and unauthenticated/forbidden access behave as designed |

For raw handshake-based HTTP fixtures, send the required content/accept and negotiated protocol
headers and handle both JSON and SSE responses. Prefer the official client's transport where
possible, but inspect the emitted wire contract. Session headers must match the chosen mode, not
old test assumptions.
