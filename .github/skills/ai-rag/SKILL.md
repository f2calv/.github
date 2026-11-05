---
name: ai-rag
description: 'Design, implement, audit or troubleshoot retrieval-augmented generation (RAG): document ingestion, PDF preparation, reviewed chunks, embedding profiles, vector storage, tenant isolation, durable inference budgets, atomic publication, retrieval evaluation and cited answers. Use for Azure OpenAI, llama.cpp or Ollama embedding pipelines and cloud versus edge comparisons. Language-neutral workflow with optional .NET guidance; infrastructure provisioning and general HTTP resilience belong to their owning skills.'
---

# Retrieval-Augmented Generation

Build a verifiable path from an authorized source to a grounded answer. Embeddings are one stage,
not evidence that retrieval or end-to-end RAG works. Keep model runtime, API protocol, embedding
space and vector store separate.

## Modes And Boundaries

- **Design:** establish ownership, storage, lifecycle and measurable acceptance before implementation.
- **Implement:** deliver one bounded stage without implying later stages are complete.
- **Audit/troubleshoot:** inspect durable state and actual runtime evidence before changing anything.
- **Compare cloud/edge:** use the same approved corpus and evaluation questions, with separate
  embedding spaces and independently authorized inference budgets.

Inspect the existing ADR, ingestion workers, provider adapters and retrieval tests before adding
another pipeline. Use [ADR authoring](../docs-adr/SKILL.md) for the decision record. Deployment,
model downloads, model loading/switching and paid or GPU inference require their own authorization;
an offline fake, metadata response or completed cloud run does not authorize them.

Read [provider contracts](references/providers-and-budgets.md) for runtime terminology,
Azure throttling and local model verification. For C# implementations, also read the optional
[.NET integration reference](references/dotnet.md).

## 1. Establish The Retrieval Contract

1. Identify the caller, tenant/collection boundary, permitted sources, retention/deletion policy,
   document rights and the questions the system must answer or decline.
2. Select the preparation method by content: text extraction, OCR/layout, tables or figures.
   Preserve physical-page and block provenance. If essential visual associations cannot be
   verified, block that document class rather than relabeling it as text-only.
3. Keep chat and embedding models independent. Define an immutable embedding profile containing
   model/revision, dimensions, metric, normalization, pooling where applicable, tokenizer,
   preprocessing and query/document prefixes or task instructions.
4. Bind stored and query vectors to compatible profiles. Equal dimensions are insufficient;
   never mix generations from different spaces. A changed profile requires a separately built and
   evaluated corpus, not padding, truncating or relabeling existing vectors.
5. Agree on representative answerable, unanswerable and cross-tenant questions plus explicit
   retrieval-quality, citation, latency and resource thresholds. Record the no-retrieval baseline.

## 2. Choose Authorities, Not Just A Vector Database

Separate original object storage, review/job authority, vector search and optional caches.
For each artifact, name its owner and transaction/delivery boundary; avoid competing authorities.
Blob storage preserves originals and version identity, but an upload event is not approval.

Choose PostgreSQL/pgvector, Azure AI Search, Redis vector search or another backend from measured
requirements: authorization filters, durable recovery, dimensions/index limits, hybrid search,
recall, operational ownership and cost. A backend's ability to store a vector does not prove its
ANN index supports that vector type/dimension. Start with exact search as a correctness baseline
when proportionate; evaluate ANN recall and filtered top-k behavior before relying on it.

For multiple index targets, persist per-target generation/publication state and retain common
source/profile identity. Do not claim a cross-service atomic transaction or dual-target readiness
when only one target completed. Derive caches from the chosen authority and define staleness and
revocation behavior explicitly.

## 3. Prepare And Review Immutable Inputs

1. Bind ingestion to an immutable object version or verified content hash. Deduplicate duplicate
   and out-of-order notifications by source identity/version, not arrival time. Acknowledge only
   after a recoverable handoff; do not make a process-local queue the sole durable record.
2. Persist preparation output with source/page/block bindings, extraction versions and quality
   findings. OCR and model-generated Markdown are drafts, not proof of fidelity.
3. Chunk by document structure and meaning, preserving headings, tables, language and source
   spans. Evaluate overlap and retrieval quality; do not pick chunk size from GPU memory alone.
4. Save an immutable review snapshot and included/excluded selection. Excluded content must not
   enter an embedding request. A successful assessment save is separate from readiness,
   execution authorization and publication.
5. Produce a deterministic manifest of included input hashes/ordinals, source and review
   revisions, embedding profile, policy revision, expected vector count and resource ceilings.
   Recheck current eligibility and observed predecessor before execution/publication.

## 4. Execute Bounded, Durable Embedding Work

Persist authorization, batch intent and provider receipts around the external side effect.
Coordinate claims, limits and publication through the durable authority across replicas; process
restarts or a different replica must not reset allowance or authorize a duplicate submission.
Reuse existing [background-pipeline](../dotnet-background-pipelines/SKILL.md) and
[HTTP integration](../dotnet-http-integrations/SKILL.md) mechanisms where applicable.

- Establish native context/batch limits and distinguish captured-token estimates from reported
  provider usage using the [provider checks](references/providers-and-budgets.md).
- Reserve the bounded request before sending. Bound SDK, handler and application retries together;
  retries must not bypass the ledger, request ceiling or cooperative deadline.
- Validate the complete response: model/profile binding, exact indexed input coverage, dimensions,
  finite values and metric requirements, plus the required native usage/receipt fields.
- Persist accepted receipts and stage vectors inactive before advancing progress. Keep rejected,
  completed and uncertain outcomes distinct.
- An uncertain post-intent outcome is not safe to replay. Reconcile only with adequate provider
  evidence and an audited transition. If recovery is deliberately deferred, record an owning TODO;
  a separately authorized full replacement must preserve the original uncertain job and its spend.

## 5. Publish Completely, Then Enforce Retrieval

Publish only when the exact authorized input set is complete, no excluded/extra vectors exist,
profile/provenance checks pass, and source/review/policy eligibility is still current. Advance a
tenant-and-collection-qualified active-generation pointer conditionally against the observed
predecessor. Keep partial and failed generations inactive and auditable.

Search only authorized, current eligible generations. Apply tenant/collection/profile constraints
at the search boundary, not just as a post-processing convenience. Verify that filtering still
returns the intended top-k/recall. Enforce source revocation and deletion even while reindexing,
replication or caches lag; do not let an old generation resurrect withdrawn content.

Return bounded passages with resolvable document/page/span citations. Treat retrieved text as
untrusted data, not instructions or tool authorization. The answering model must distinguish
evidence from speculation and abstain when evidence is insufficient. Verify access again when
serving originals or citation previews.

## 6. Verify And Report By Milestone

Use focused, authorized tests: deterministic fakes for malformed/partial responses, duplicate
events, quota coordination and ambiguous intent; real storage for locking/publication/filtering;
separately approved live provider probes for actual identity, dimensions, usage and GPU fit.
A health endpoint, build or source-declared test is not acceptance of these behaviors.

Evaluate retrieval before answer fluency: expected passage recall/ranking, exclusions, tenant
isolation, profile mismatch and stale-source rejection. Then measure citation correctness,
grounded answers/abstention, prompt-injection resistance and latency/cost against the baseline.

Report **prepared**, **reviewed**, **embedded**, **published**, **searchable** and **grounded**
separately, with exact counts, tested thresholds and remaining gates. Distinguish implemented,
offline-tested, deployed and live-accepted. Include native usage and timing without document/query
content or private deployment coordinates in exported telemetry.

## Maintaining This Skill

- Provider API routes, metadata guarantees, native token accounting, context and batching behavior.
- Azure quota scopes, SDK retry defaults and embedding deployment/version semantics.
- llama.cpp/Ollama revision, pooling, model-loading and usage-response contracts.
- Vector-index dimension/type limits, filtered ANN recall and generation-publication guarantees.
- Evaluation cases and new RAG-specific lessons; keep generic HTTP, DI and storage rules with
  their existing owners and implementation-specific details in the references.
