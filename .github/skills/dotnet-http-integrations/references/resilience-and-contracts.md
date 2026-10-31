# HTTP Resilience and Contract Boundaries

## Select Safe Retry Semantics

The standard resilience handler can retry methods whose side effects are not safe to repeat.
Do not install it without reviewing operation semantics. Use `DisableForUnsafeHttpMethods` where
supported to prevent automatic retry of POST, PATCH, PUT, DELETE and CONNECT, then make any
operation-specific exception deliberate. HTTP method classification alone is not proof that an
upstream GET is side-effect-free or a PUT is safely replayable.

| Operation | Baseline policy | Evidence needed for more |
| --- | --- | --- |
| Read with no side effects | Bounded retries for documented transient failures | Total budget, upstream limits and replayable request |
| Create/send/payment-like mutation | No automatic replay | Stable idempotency key and documented server deduplication/recovery semantics |
| Idempotent mutation | Conservative no-retry baseline | Verified endpoint contract and repeatable body |
| Streaming upload/download | Explicit resume/restart policy | Rewindability, size limits and partial-effect recovery |

Timeout after a mutation is ambiguous: the server may already have committed. Do not report “not
performed” or blindly resend with a new key. Use the existing status/reconciliation operation.
Keep the same logical idempotency key across authorized retries, not a new one per attempt.
Authentication refresh retries and outer job retries count toward the same replay/budget analysis.
Hedging can send concurrent duplicates; do not enable it for unsafe operations.

## Budgets and Handler Order

Choose one overall operation deadline, bounded attempts and appropriate per-attempt timeouts.
Account for queue/rate-limit waits, retry delays, connection establishment and body consumption.
`HttpClient.Timeout` can race resilience timeouts; configure the chosen ownership intentionally
rather than layering conflicting defaults. With `ResponseHeadersRead`, explicitly bound/cancel body
reads too; receiving headers is not successful completion of the operation.

Respect documented `Retry-After` and quota behavior within the overall deadline. Avoid holding an
application lock while waiting/retrying. Circuit-breaker scope must match the dependency isolation
needed; do not assume one handler creates a globally shared circuit across replicas.

Inspect actual handler ordering. A token attached outside a retry loop may remain stale across
attempts; refreshing credentials may itself trigger replay. Authentication belongs on the intended
request/destination, never on a global mutable header used concurrently for different identities.
Automatic redirects also need review where credentials or signed URLs could cross origins.

## Lifetimes and Credentials

Factory handlers have their own DI scopes, which are not request scopes. Do not cache request
identity or scoped tenant state in a pooled delegating handler. Pass operation context explicitly
using the existing safe mechanism and ensure credentials are not leaked across users.

Long-lived services can inject `IHttpClientFactory` and create named clients per operation.
Avoid retaining transient typed clients indefinitely; verify configured handler/connection lifetimes
and DNS refresh. Review cookie-container sharing if the external service uses cookies.
Do not manually dispose factory-owned inner handlers.

Coordinate token refresh with a concurrency-safe expiry policy and a testable clock. Keep secrets
in the existing configuration/credential store; do not persist refresh responses as debugging aids.
Retry only the documented authentication failure case, not every forbidden response.

## Results, Pagination and Streaming

When consuming versioned resources, prefer upstream conditional/version-bound operations. Metadata
checks before and after a request detect observed drift but cannot prove a mutable tag was not
changed and restored between reads. Without atomic upstream binding, document the operator's
immutability requirement instead of claiming revision certainty.

Keep local quota estimates distinct from provider-native usage when their units or tokenizers
differ. Record authoritative native counters, disable silent truncation where supported, and
document that detecting an overrun cannot undo work already performed.

Map recognized upstream errors to the application's expected result/exception contract.
Keep status, safe error category and actionable context, not raw bodies or sensitive URL queries.
Bound any diagnostic body inspection and redact before logging/throwing; some APIs return HTML,
personal data or credentials in errors.

Validate required payload fields and content type. Do not deserialize a success DTO from a failed
status. A page failure is not an empty last page; do not silently return a partial collection as a
complete result. Bound pages/results and detect repeated continuation tokens.
Resolve continuation URLs only within the approved destination/authentication policy.

Dispose responses/requests/streams at their documented ownership boundary, including failed
deserialization and cancellation. A returned stream must retain the resources it needs until the
caller disposes it; a `using` in the factory method can otherwise close it prematurely.
