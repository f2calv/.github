---
name: ai-edge-inference
description: 'Configure, tune, evaluate and troubleshoot local or edge model inference: GPU/host memory budgets, GGUF quantization, context, concurrency, multimodal support, loading and throughput. Use when running llama.cpp or Ollama, maximizing useful GPU residency, comparing edge models or diagnosing slow loads and OOM failures. Runtime-specific guidance stays in separate references; ai-rag owns retrieval pipelines and embedding-space contracts.'
---

# Edge Inference

Optimize for a measured workload within memory, latency and quality constraints, not the highest
memory allocation. Keep reusable inference decisions here and deployment ownership, manifests,
hardware inventories and benchmark harnesses in their consuming repository.

## Modes And Boundaries

- **Configure/tune:** preserve a working baseline and change one bounded parameter group at a time.
- **Compare:** hold workload and evaluation criteria constant; record runtime-specific differences.
- **Troubleshoot:** classify the failure from effective configuration, logs and measurements before
  changing memory limits or model selection.

Read the [llama.cpp reference](references/llama-cpp.md) only for that runtime. Ollama is a separate
configuration and lifecycle surface: inspect its installed version and official documentation;
do not translate llama.cpp flags or router behavior into Ollama settings. Add verified Ollama
procedures in a separate reference when evidence is available, not as speculative defaults.

Use [RAG guidance](../ai-rag/SKILL.md) for retrieval and embedding-space contracts. Inference
runtime tuning does not establish retrieval correctness or authorize corpus processing.

## 1. Discover The Current Execution Boundary

1. Read the consuming repository's current instructions and operational adapter. Rediscover the
   owning configuration, runtime process and callers; historical paths and cluster names are not
   evidence of the current topology.
2. Record runtime version/build or image digest, backend and driver, accelerator count and memory,
   host RAM/container limits, storage path and model artifact identity/revision/quantization.
3. Inspect the running process, effective configuration and startup logs. A configured GPU count,
   model alias or advertised modality is not proof of actual offload or enabled capability.
4. Establish required modalities, languages, tools/structured output, prompt length, output reserve,
   concurrency, quality floor and latency target before choosing a model or context budget.
5. Separate authorization for inspection from downloads, model loading/switching, inference and
   deployment changes. Agree on a bounded run and restoration conditions before disrupting callers.
   Preserve authentication; use an authorized local-only tunnel when appropriate.

## 2. Budget Memory Before Choosing A Quant

Budget resident weights, KV or recurrent state, compute/workspace buffers, multimodal projector
and image processing, runtime overhead, other consumers and explicit headroom. Account for host
RAM and GPU memory separately on discrete GPUs; on unified-memory systems avoid double-counting
shared capacity and reserve memory for the OS. For multiple GPUs, check each device's allocation
and split, not just aggregate capacity.

- Treat artifact size and parameter count as estimates, not measured resident or peak memory.
  For mixture-of-experts models, active parameter count is not total resident weight size.
- Context, concurrent slots, cache dtype and architecture change state allocation differently.
  Determine whether configured context is total or per slot for the installed runtime.
- Prefer full GPU residency when it meets the quality target; partial offload can be legitimate
  when capacity or quality requires it, but measure its latency and host/interconnect cost.
- Start with a fitting candidate and representative context. Increase weight quality, context or
  concurrency according to the workload, one at a time; stop before unstable peaks or exhausted
  headroom. Lower-bit weights and KV can alter correctness and must be reevaluated.
- Keep safety margin based on observed worst-case prefill, generation and modality peaks rather
  than a universal percentage or a hardware-specific preset.

## 3. Verify Configuration And Capability

Resolve supported controls from the installed runtime, not a remembered command line. Establish
which layer owns model selection, offload, context, batching, cache types, concurrency, idle
residency, reasoning and output limits; verify the effective values after startup.

Validate the actual chat template/tokenizer, model artifact and any compatible projector. Probe
text, tool calls, structured output and image/audio support separately using approved synthetic
inputs. Model-family marketing or a metadata flag alone does not establish capability. Do not
globally disable reasoning or impose a small output budget and then call the result a fair model
comparison. Unsupported behavior, truncated output and incorrect output are different outcomes.

## 4. Measure And Diagnose

Follow the [measurement reference](references/measurement.md) for reproducible runs, result
classification, memory sampling and storage/interconnect diagnosis. Reuse an existing local harness
instead of introducing another benchmark framework.

When a candidate fails, distinguish download errors, startup contention, eviction, unsupported
runtime/model combinations, allocation failure, timeout and request/schema failure. A timeout is
not proof that the model cannot fit. Correlate lifecycle logs with the observation interval.

## 5. Restore And Report

Use the consuming repository's approved deployment workflow. On reconciled systems, a direct
scale or patch may be undone; identify the desired-state owner before an authorized change.
Do not disable reconciliation, remove caches or reboot nodes as an incidental benchmark step.

Restore the agreed baseline and caller availability on success, failure or interruption. Verify
readiness, loaded artifact and caller recovery rather than reporting only that a restore command
was issued. Report changed settings, measurements, limitations, incomplete cases and whether
restoration was verified. Keep run artifacts and hardware-specific recommendations local; do not
copy private operational identifiers or user media into this shared skill.

## Maintaining This Skill

- Runtime upgrades: recheck option names, precedence, context/slot semantics, lifecycle APIs,
  backend offload and model/template/projector support against the installed build.
- New architectures and cache formats: revisit memory assumptions and quality checks rather than
  carrying forward dense-transformer estimates.
- New Ollama evidence: add a separately sourced reference without importing llama.cpp semantics.
- Benchmark API/usage changes: verify timing units, token counts, failure persistence and memory
  sampling; keep hardware-specific scores and deployment adapters outside the shared skill.
