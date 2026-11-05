# Edge Inference Measurement And Diagnosis

Use a bounded, authorized workload to compare configurations. Persist evidence locally without
turning one machine's model scores into general recommendations.

## Run Contract

Record runtime/build, model and projector identities, effective settings, hardware/driver, storage,
other consumers, prompt/template, generation settings, context, concurrency and cache conditions.
Separate download, initialization, warmup and steady-state requests. Label resident, OS-page-cache
warm and cold runs explicitly; a server restart does not guarantee cold storage caches.

Keep the baseline and candidate workload comparable. Use representative prompt lengths, output
budgets, languages and modalities rather than only a short readiness completion. Record reasoning
policy; a seed and temperature zero improve repeatability but do not guarantee deterministic GPU
execution. Report repetitions and distributions as well as failures, not just the best sample.

Before a long matrix, verify one complete case and resumable output. Persist each completed case
and each failure incrementally so an exception cannot erase earlier results. Run serially when
models compete for a resident slot, and record interruptions from unrelated consumers.

## Metrics And Outcomes

| Measurement | Required distinction |
| --- | --- |
| Load duration | Request-to-ready boundary, eviction/download inclusion and polling resolution |
| Effective load MiB/s | Named artifact-byte denominator divided by measured load time; not raw disk or PCIe bandwidth |
| Prompt processing | Native prompt tokens/time, prompt cache hits and input length |
| Decode throughput | Native generated tokens/time, output length and reasoning-token accounting |
| User latency | Nonstreaming total latency versus streaming time-to-first-token and end-to-end time |
| Memory | Per-device idle baseline, post-load residency and sampled peaks during prefill/decode/multimodal work; host RAM separately |
| Correctness | Per-case rubric, raw outcome classification, coverage and known scoring limitations |

Use authorized `nvidia-smi` sampling on NVIDIA hosts or the platform's equivalent, correlated with
model lifecycle and requests. A post-request snapshot misses transient peaks; the GPU reading alone
does not prove full offload. Retain sampling interval, observed maximum and log evidence of actual
offload. For unified memory, also observe system pressure and swapping.

Classify unsupported, not run, request failure, load failure, timeout, empty output, truncated
output and incorrect output independently. Unsupported/not-run rows have no quality score, not
zero. Preserve successful timings even when output is wrong, but exclude failed requests from
successful-throughput aggregates and report the failure count.

Tool tests check nested argument names, values and types. Translation evaluation separates meaning,
grammar, dictionary accuracy and genuinely valid alternatives; regex coverage and distinct-string
counts are only heuristic regressions. Use bilingual review or a validated evaluation set for
quality claims. Vision cases need independently known facts, multiple examples and an explicit
spatial/OCR rubric. Use synthetic or rights-cleared fixtures, not private user media.

Keep arithmetic labels precise: mean of per-model speedups and ratio of mean durations are different
statistics. Record missing observations rather than filling a fresh table with historical VRAM or
inference measurements. A load-only retest does not update quality or steady-state throughput.

## Slow Loading Versus Slow Inference

1. Check lifecycle logs first: download, deserialization, page-in, GPU allocation, graph setup,
   readiness, eviction and retries are different phases. Confirm no competing caller is switching
   the model during the observation window.
2. Identify the actual model-cache filesystem and storage transport. On Linux, inspect read-only
   mount/block information and `lsusb -t` where USB is involved. A fast disk can negotiate at USB 2
   because of a cable, hub or port; distinguish negotiated link speed from advertised drive speed.
   Compare cache warmth and storage activity before blaming model architecture.
3. Inspect PCIe generation and lane width separately, under representative load as well as idle.
   Idle power management can downshift link speed; a GPU's x16 capability does not mean the host
   connection provides x16 lanes. Approximate per-direction Gen1/Gen2/Gen3 x1 ceilings are
   250/500/985 MB/s before protocol overhead; these are not guaranteed model-load rates.
4. Fully resident decoding usually depends more on GPU compute and memory bandwidth than host-link
   speed. Partial offload, host-resident state and repeated transfers make the interconnect more
   important. Measure prompt processing and decoding separately before proposing a hardware change.
5. Confirm host memory pressure, swap, thermal/power limits and other GPU processes. Distinguish
   GPU allocation failures from container/host OOM kills and runtime incompatibility.

Do not clear shared page/model caches, change link settings, replace drivers or reboot as an
automatic diagnostic. Establish a separate approved experiment with recovery conditions when a
read-only observation cannot resolve the hypothesis.
