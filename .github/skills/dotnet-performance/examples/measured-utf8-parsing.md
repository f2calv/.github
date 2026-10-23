# Measured UTF-8 Parsing

Use the [runnable fixture](./utf8-count/README.md) when the application already has UTF-8 bytes
and profiling shows that decoding them solely to parse a count is a meaningful hot path.
It is not evidence that parsing dominates an arbitrary application.

## Compare One Change

The baseline decodes the existing buffer with `Encoding.UTF8.GetString` and parses the resulting
string. The candidate calls the framework's UTF-8 `int.TryParse` overload directly. Both use
`NumberStyles.None`, invariant culture and the same `Int32` result.

The third variant copies the already suitable byte array before direct parsing. It is intentionally
unnecessary: a span API does not remove allocations the caller introduces with `ToArray()`.
Keep it as a measured rejected option, not production code.

## Correctness Before Timing

Run the fixture's 16 cases before benchmarking. They check boundaries, failure outputs, malformed
UTF-8 and equivalence with the original parser. In particular, the framework accepts trailing NUL
bytes here. A stricter protocol grammar is a separate behavioral requirement, not an optimization
to smuggle into this change.

The benchmark checks equal results during setup and returns each result from the timed method.
Never compare a baseline that performs validation or returns a useful value with a candidate that
silently omits the same work.

## Measurement Contract

Use Release without a debugger, two launches, three warmups and five measured iterations per launch,
with MemoryDiagnoser. Record the SDK/runtime, OS/architecture, input shape, job settings, mean/error
and bytes per operation. Keep machine names, local paths and raw generated reports out of public
documentation.

This is a short microbenchmark on one nine-byte valid input, not a throughput or latency SLO.
Do not set CI timing gates from its numbers. Recheck the real application's input distribution,
failure rate, ownership/lifetime and CPU/runtime before adopting it.

## Decision

Measured on 2026-10-23 using BenchmarkDotNet 0.15.8, .NET SDK 10.0.402, runtime 10.0.13,
Windows x64 and the existing workstation power plan. The short job above completed all three
benchmarks with two launches each:

| Variant | Mean | Error margin | Allocated per operation |
| --- | --- | --- | --- |
| Decode then parse | 68.92 ns | 27.53 ns | 40 B |
| Direct UTF-8 parse | 31.76 ns | 1.77 ns | 0 B |
| Copy then parse | 62.40 ns | 3.98 ns | 40 B |

The error column is BenchmarkDotNet's reported confidence-interval margin, not an application
latency bound. Baseline timing was noisy on this shared workstation, so do not turn the point
estimates into a precise speedup claim. The clear result is removal of the 40-byte allocation
for this input, with the same tested behavior. The unnecessary copy restores the allocation and
costs more time than the direct path; reject that variant.

Keep direct parsing only where this saving matters to the measured application hot path.
Re-run with representative inputs and a longer controlled job before making broader throughput
claims, and repeat after runtime/dependency changes rather than treating this snapshot as permanent.
