# Explicitly Authorized Actions

Load only when the user has separately authorized a write-capable MCP tool.

When the user separately authorizes a write capability, keep it in an explicitly registered action
facade behind its own off-by-default gate. Reuse the application's domain service; never bypass
policy through a raw upstream client. Reuse its request validation and bound model-controlled input.

Describe the real side effect and require clear user intent for destination and content; prompt
guidance or a model-supplied confirmation flag is not authorization. Review whether every caller
with network access would gain the action before enabling it.

Set annotations from actual behavior: sending externally is not read-only or idempotent, even when
it is additive rather than destructive. Return minimal acknowledgements, not echoed sensitive input,
and distinguish upstream acceptance from confirmed delivery.

When a physical or security-sensitive action needs human approval, enforce it on the MCP server that
owns the action, not in the client or prompt: mark the method with an attribute and gate it in a
`WithRequestFilters(f => f.AddCallToolFilter(...))` filter. In SDK v2.3.0 the tool is matched before
call-tool filters run, so `context.MatchedPrimitive` is the `McpServerTool` and its `Metadata` holds
the method attributes. Fail closed when the approval channel is unavailable, decide the answer in code
rather than through a model, and return a refusal result rather than an error. A client can identify
the calling agent with `McpClientTool.WithMeta(...)`; treat that `_meta` value as display-only.

Audit the complete retry and logging path, including dependency libraries. Unless durable request
deduplication exists, do not replay an outcome-uncertain operation automatically. Propagate caller
cancellation and warn that timeouts or failures may occur after the action completed. Test through
fake domain services and HTTP handlers; never send live messages merely to verify the tool.
