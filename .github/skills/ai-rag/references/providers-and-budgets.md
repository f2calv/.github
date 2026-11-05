# Provider Contracts And Inference Budgets

Use this reference before selecting an embedding connector or authorizing cloud/edge execution.
Verify the deployed version and configuration; examples, enum members and old manifests are not
evidence of a running provider.

## Runtime, Protocol, Connector And Model

| Layer | Meaning | Examples |
| --- | --- | --- |
| Runtime/service | Software or managed service executing inference | llama.cpp, Ollama, Azure OpenAI |
| HTTP interface | Routes and request/response semantics | OpenAI-compatible `/v1/embeddings`; Ollama-native `/api/embed` |
| Application connector | Client/adapter implementing that interface and its required checks | OpenAI client, OllamaSharp, explicit runtime-specific adapter |
| Model artifact | Weights, revision, quantization and execution conventions | A pinned GGUF artifact or verified Ollama model digest |
| Vector backend | Storage/search, independent of the inference runtime | pgvector, Azure AI Search, Redis vector search |

Use **llama.cpp** in prose, **LlamaCpp** in PascalCase identifiers and **llama-cpp** for
kebab-case resource identifiers when that matches repository conventions. Use **OpenAI-compatible**
for its supported OpenAI-style routes, not **Ollama-compatible**. Ollama exposes a native API and
also a subset of the OpenAI API; that does not make the runtimes or their native adapters identical.

Keep a genuinely Ollama-native adapter named for Ollama. A llama.cpp adapter may appropriately
carry runtime-specific identity/metadata checks even when its inference POST is OpenAI-compatible.
Use protocol-generic names only when the implementation really is generic. Do not rename external
SDK types, valid configuration discriminators or legacy runtime resources just for consistency.
Describe a preferred runtime as a project choice, not a universal performance/quality ranking.

Microsoft.Extensions.AI supplies provider-neutral `IChatClient` and `IEmbeddingGenerator`
abstractions. Its OllamaSharp examples are not a requirement to use Ollama: OpenAI client adapters
can target compatible services. Compatibility remains route/model/capability-specific; chat
success does not prove embeddings, vision, Responses, structured output or native usage support.

Official references:

- [llama.cpp server routes and embedding contracts](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md).
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility).
- [Ollama native embedding API](https://docs.ollama.com/api/embed).
- [Microsoft.Extensions.AI abstractions](https://learn.microsoft.com/en-us/dotnet/ai/microsoft-extensions-ai)
  and [concrete chat-client implementations](https://learn.microsoft.com/en-us/dotnet/ai/ichatclient#implementation-examples).

## Azure And Other Managed Providers

1. Resolve the actual embedding deployment, model/version, native or selected dimensions,
   identity permissions and workload-network reachability. A deployment name is not necessarily
   a model name. Metadata and a separately authorized bounded probe establish different facts.
2. Read current quota, request and input limits for the deployment type, region and model.
   Limits may be shared across logical application profiles or other callers. Coordinate against
   the real quota scope, not a tenant label or one worker's memory.
3. Pack from captured inputs conservatively, but retain their tokenizer and measurement unit.
   An admission estimate is not the provider's native tokenizer or billing receipt. Never label
   estimates as reported usage or substitute them for a required native receipt.
4. Persist pacing/reservations in shared durable state. Include concurrent callers, restart
   behavior and authoritative rejection/retry-after evidence. Native token limits, estimated
   admission tokens and rate-limit accounting can differ.
5. A small PDF can still exceed a low-throughput allocation: many chunks plus a large batch may
   burst past the applicable rolling/short-window limit. Explain observed deployment capacity,
   batch sizes, native usage and request spacing rather than blaming file size alone.
6. Diagnose before requesting IaC changes: batching/pacing bugs are application work; missing
   deployment/identity/network prerequisites or an approved capacity increase are infrastructure
   handoffs. Capacity does not repair ambiguous-intent recovery or grant more spend.

No universal batch size, token allowance or sleep interval belongs in the application policy.
Derive configured bounds from verified limits and an explicit authorization. A bounded provider
rejection may permit a policy-controlled retry; an unknown outcome does not. Confirm SDK and
resilience-handler retry behavior, including streaming/body-read failures.

Official references:

- [Azure OpenAI quotas and limits](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/quotas-limits).
- [Azure OpenAI rate limits](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/quota).

## llama.cpp And Other Self-Hosted Runtimes

1. Discover the running process/image, endpoint, advertised models and launch configuration.
   Establish actual physical GPU memory, current residency, other workloads and container limits;
   scheduler resource counts or time-sliced allocations are not physical-GPU inventory.
2. Select a dedicated single-model embedding endpoint when proportionate. If sharing a router,
   explicitly verify selection, autoload/unload, concurrency and model-switching behavior. A GET
   request is not automatically free of model-loading side effects.
3. Pin the immutable artifact revision, quantization, tokenizer, dimensions, pooling, normalization
   and query/document conventions. A display alias containing a SHA256 is not cryptographic
   attestation that the running process loaded those bytes. Independently verify the file and
   launch configuration; metadata may not expose effective pooling or embedding enablement.
4. Verify source-level/runtime context and batching behavior for that version. Snapshot token
   counts cannot establish a different model's native context fit. llama.cpp rejects over-context
   embeddings; additional physical-batch restrictions depend on pooling and runtime behavior.
   Do not send an Ollama-only `truncate=false` option to llama.cpp as an invented guarantee.
5. For native Ollama, verify the installed digest, embedding capability, dimensions and supported
   truncation policy through its own contract. Do not download/pull models implicitly. Apply the
   shared [mutable-model binding limits](../../dotnet-http-integrations/references/resilience-and-contracts.md#results-pagination-and-streaming)
   when deciding whether metadata evidence is sufficient for publication.
6. With separate approval, probe one representative bounded input, then the largest admitted
   input/batch. Verify native usage, ordering, dimensions and vector validity. Measure weights
   plus context/batch/scratch allocations and co-resident chat load; file size alone is not VRAM fit.
7. Prefer explicit scheduling/model residency over hidden fallbacks. Unload requests may trade
   idle memory for reload latency and do not control other callers. Do not switch a shared chat
   server into embedding mode or evict its model without authorization.

Preserve the accepted cloud generation during edge experiments using a separate corpus/publication
pointer when comparison requires both to remain available. Never compare answers by silently
embedding queries in the wrong space.

Official references:

- [llama.cpp embedding and metadata implementation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/server-context.cpp).
- [Ollama model inspection](https://docs.ollama.com/api/show) and
  [embedding usage fields](https://docs.ollama.com/api/embed).
- [pgvector supported vector/index types](https://github.com/pgvector/pgvector#supported-types).
