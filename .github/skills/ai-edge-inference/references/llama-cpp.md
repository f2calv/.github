# llama.cpp Runtime Configuration

Use this reference after discovering the installed llama.cpp build. Controls below are tuning
surfaces to verify, not a universally compatible command line or recommended preset.

## Establish The Effective Configuration

Inspect the matching build's `llama-server --help`, startup logs and
[upstream server documentation](https://github.com/ggml-org/llama.cpp/tree/master/tools/server).
Record an immutable build/digest alongside results; a moving image tag does not identify a build.
Treat upstream main as discovery material, not proof that a deployed older build supports a flag.

Distinguish a single-model server from router/preset mode. Where supported, inspect
`--models-preset`, `--models-max`, the startup selection and per-model load policy. Confirm how
command-line arguments, environment variables, global preset entries and model sections merge.
Do not assume a per-model override wins over a process-level argument. Keep workload-dependent
settings per model when the installed preset implementation supports it, then verify the child
process's effective arguments and logs.

| Surface to verify | Decision and evidence |
| --- | --- |
| `--n-gpu-layers` / `n-gpu-layers` | Requested offload versus actual layers/tensors and backend allocations in logs; a high value requests rather than proves full residency |
| `--ctx-size` / `ctx-size` | Required prompt plus generation reserve; actual context per sequence and total cache allocation |
| `--parallel` / `parallel` | Concurrent sequences, context division/allocation and peak memory under overlapping requests |
| `--flash-attn` / `flash-attn` | Backend/model support and effective enablement; check cache-type compatibility |
| `--cache-type-k`, `--cache-type-v` | Supported cache quantization, allocation reduction and quality at representative context lengths |
| `--batch-size`, `--ubatch-size` | Logical/physical prompt-processing batches; throughput versus workspace peaks and latency |
| `--n-predict` and request token limit | Effective output cap, finish reason and enough budget for reasoning plus the requested answer |
| Reasoning/template controls | Exact supported syntax and generated reasoning behavior; do not assume one model's controls apply to another |
| Projector and multimodal controls | Compatible artifact, enabled encoders, image processing cost and successful typed-content request |

Use the global workflow's memory budget before increasing these controls. Quantized KV with Flash
Attention can reduce memory, but supported combinations and quality vary with build and model.
Avoid presenting a fixed context size, unlimited-looking layer count or cache dtype as a safe
default for every accelerator.

## Model Identity And Modality

Record repository revision/file or digest, quantization, tokenizer/template and projector identity.
Verify that requested model names exist; ask about an ambiguous family/version rather than silently
substituting another model. A router alias is not an immutable artifact identifier.

Prefer explicit, distinct text and multimodal aliases when the deployed router supports them.
Check the exposed IDs after loading: preset names may be normalized or collide in some builds.
Metadata can lag actual enabled modalities; verify projector logs and a real approved image request
before marking vision supported or unsupported. Text-only controls such as `no-mmproj` and their
translation into process flags are version-specific. Do not infer audio support from vision support.

## Lifecycle And Router Contention

Discover the deployed API contract before scripting it. Some router builds expose `GET /models`,
`POST /models/load` and unload operations; OpenAI-compatible `/v1/models` alone does not establish
their availability. Verify response envelopes, exact IDs, load-state fields and request bodies.
Poll a bounded readiness condition and detect explicit failure, not just elapsed time.

A single-resident-model configuration can evict a benchmark candidate when another caller requests
the baseline. Startup loading may also occupy the slot and reject a second load. Correlate caller
activity and load/unload logs before declaring OOM. Record whether each run reused a resident model
or triggered loading, and separate artifact download from initialization.

## Request Validation

For supported OpenAI-compatible chat endpoints, validate the deployed request schema rather than
assuming identical behavior to a hosted provider. Preserve `messages` as an array even for one
message. Multimodal content is an array of typed text/image parts; a serializer accidentally
unwrapping either array can produce a request failure unrelated to model quality.

Validate tool name, parsed argument object and nested values/types. Valid JSON is not proof of
schema conformance or correct tool use. Where supported, structured-output constraints can improve
shape but do not validate semantic correctness. Preserve finish reason and classify empty output,
token-limit truncation, invalid request and wrong answer separately.
