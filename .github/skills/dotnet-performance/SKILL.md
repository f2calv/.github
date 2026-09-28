---
name: dotnet-performance
description: 'Optimize measured .NET hot paths: ValueTask signatures, span and UTF-8 parsing, SearchValues, frozen collections, PipeReader loops, pooled buffers, inlining and allocation-free logging. Use when profiling or tuning channel readers, stream consumers, parsers, caches or other tight loops.'
argument-hint: '[scope=file|project] [mode={review|optimize}]'
user-invocable: true
---

# .NET Performance

Apply these patterns only where measurement shows a meaningful hot path. The everyday defaults —
sealed classes, `ValueTask` correctness, `ConfigureAwait(false)` in libraries, frozen collections,
`System.Threading.Lock` and `[LoggerMessage]` on hot paths — live in the shared C# instructions and
are not repeated here.

## Workflow

1. Identify the hot path from evidence: BenchmarkDotNet, `dotnet-counters`, `dotnet-trace`, or a
   representative load test. Record the baseline and the measurement conditions.
2. Change one pattern at a time and re-measure. Keep a change only when it produces a meaningful,
   repeatable gain; revert complexity that does not.
3. Ask before running benchmarks or load tests, and report figures with their conditions.

## Asynchronous Signatures

- Prefer `ValueTask<T>` on hot-path interfaces — channel brokers, cache accessors, `TryRead` wrappers
  — so implementations avoid a `Task` allocation when data is already available.
- Keep `Task<T>` for operations that almost always complete asynchronously, such as HTTP, database
  and file I/O.

## Parsing

- Parse UTF-8 input directly from `ReadOnlySpan<byte>` (`PipeReader`, network buffers); do not
  materialise a `string` first.
- Offer `ReadOnlySpan<char>` overloads for caller convenience only; they are no faster than the
  `string` overload for strings that already exist. Implement the span version and let the string
  overload delegate through `.AsSpan()`.
- Use a static `SearchValues<char>` or `SearchValues<byte>` field for repeated `IndexOfAny` or
  `ContainsAny` over a fixed delimiter set, so the runtime selects a vectorised implementation.

## Collections

- Build startup-only lookups with `.ToFrozenDictionary()` / `.ToFrozenSet()` at the end of
  initialisation, and store them as the concrete frozen type so lookups can be devirtualised.

## Tight Loops

- Use `stackalloc` or `ArrayPool<T>` for temporary buffers instead of `new byte[]`.
- Slice `ReadOnlySequence<byte>` rather than calling `.ToArray()`.
- Use `PipeReader` for line-oriented binary streams and process data in place from its buffer.
- Apply `[MethodImpl(MethodImplOptions.AggressiveInlining)]` only to small leaf parsing or
  conversion methods called in tight loops; the JIT already inlines small methods, and complex
  control flow does not benefit.
- Convert loop logging to source-generated `[LoggerMessage]` to remove `params object[]` boxing.

## Reporting

Report the hot path, baseline and after figures with conditions, each pattern applied, and any
pattern rejected because it did not measurably help.
