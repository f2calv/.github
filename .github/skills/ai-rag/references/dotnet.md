# .NET RAG Integration

Apply the language-neutral lifecycle in this skill without introducing a second .NET architecture.
Use the repository's existing composition, typed configuration, persistence and test platform.

## Contracts And Composition

Use `IEmbeddingGenerator<string, Embedding<float>>` from Microsoft.Extensions.AI where it preserves
the required contract, and `IChatClient` for answering. The abstractions do not attest model
revision, enforce tenant policy, journal submissions or publish generations. If a connector drops
required usage/identity fields, retain an explicit typed provider adapter rather than silently
weakening receipt validation.

Keep preparation, profile resolution, embedding execution, vector persistence, authorized retrieval
and answer orchestration as explicit responsibilities. Reuse an existing application-owned provider
boundary; do not create an interface or project per runtime merely to name a pattern.
The [ports-and-adapters workflow](../../patterns-ports-and-adapters/SKILL.md) owns dependency
direction and provider substitution.

Compose provider adapters and persistence with
[dependency-injection guidance](../../dotnet-dependency-injection/SKILL.md).
A scoped adapter is not the Singleton pattern; report actual patterns and lifetimes accurately.
Use [AppHost composition](../../dotnet-apphost/SKILL.md) for feature/role registration and worker
startup; registration alone does not prove an execution path is enabled.

## HTTP And Durable Workers

Use the [HTTP integration workflow](../../dotnet-http-integrations/SKILL.md) for factory-managed
clients, endpoint policy, credentials, bounded bodies, cooperative deadlines and the combined SDK/
handler retry budget. Keep runtime-specific metadata and inference serialization in their adapter;
do not make an OpenAI-compatible POST imply generic runtime verification.

Use [background pipelines](../../dotnet-background-pipelines/SKILL.md) for supervision, backpressure
and cancellation. Keep durable claim/intent authority outside process-local channels. Leadership
alone does not fence stale workers or prove that a paid request was not accepted. Follow existing
[leadership-election guidance](../../dotnet-leadership-election/SKILL.md) when distributed ownership
is actually needed; do not add another election mechanism just for embeddings.

## Storage And Search

Use the existing [EF Core workflow](../../dotnet-efcore/SKILL.md) for mappings, provider-backed
queries, transactions, migrations and rolling compatibility. Apply its
[snapshot equality and receipt-binding rules](../../dotnet-efcore/references/queries-and-writes.md#writes-and-conflict-handling)
to manifest hashing and round-trip tests through the real database representation.

Check pgvector provider mapping, stored dimensions, index type limits and SQL filtering separately.
Keep query-profile selection and tenant/current-eligibility predicates inside the authorized
retrieval operation. Do not infer native SQL/index correctness from an in-memory LINQ fake.

Use the [Redis workflow](../../dotnet-redis/SKILL.md) for selected Redis key roles, retention and
cache consistency; do not assume Redis is only a cache or automatically the vector authority.
Object storage credentials, source download authorization and browser upload permissions remain
separate from embedding execution permission.

## Focused Validation

Use the repository's established runner and ask before execution. Separate deterministic fake-HTTP
cases, real database coordination/search cases, composition/lifetime checks and explicitly opted-in
live-provider cases. Guard credentials and inference independently; a configured endpoint is not
test consent. Keep production/debug conditional registration and source/package reference variants
visible in the test plan.

Verify complete indexed responses, malformed/missing native usage, dimension/model drift,
post-intent cancellation, duplicate claims, quota sharing, publication races and revoked-source
retrieval. A provider adapter test cannot establish database atomicity or an end-to-end grounded
answer. Report actual executed cases and the exact behavior proven.

Official reference: [Microsoft embedding-generator abstractions](https://learn.microsoft.com/en-us/dotnet/ai/iembeddinggenerator).
