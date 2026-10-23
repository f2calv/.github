# UTF-8 Count Parsing Example

A small .NET 10 fixture showing how to remove a decoded-string allocation without changing the
intended parsing behavior. It contains a source-only library, correctness tests and a benchmark;
nothing is packaged or published.

## Projects

| Project | Purpose |
| --- | --- |
| [Example.CountParsing](./src/Example.CountParsing/README.md) | Consumer-facing UTF-8 API and behavior |
| [Example.CountParsing.Tests](./src/Example.CountParsing.Tests/README.md) | Correctness and baseline-equivalence cases |
| [Example.CountParsing.Benchmarks](./src/Example.CountParsing.Benchmarks/README.md) | Three comparable timing/allocation paths |

## Validate

On Windows, first copy this self-contained fixture to a fresh, short temporary directory.
BenchmarkDotNet creates a deep generated-project tree under the executable's output directory;
running from a long checkout/session path can fail before measurement. This is a fixture copy,
not a second Git checkout. Keep generated output outside the central repository.

After approval, from this directory:

```console
dotnet test --solution Example.CountParsing.slnx --configuration Release
dotnet run --configuration Release --project src/Example.CountParsing.Benchmarks -- --filter "*CountParsingBenchmarks*" --artifacts <temporary-output-directory>
```

Tests run before measurement. The benchmark input is the already-buffered UTF-8 value `123456789`;
its allocation is excluded from timing. No network service, credential or production data is used.
Dependency restoration may access the configured NuGet sources.

The central repository's `dotnet-examples` CI job builds this solution in Release and runs the
parsing tests with `--minimum-expected-tests 16`. Benchmark execution is deliberately not part of
CI. When adding test cases, keep the expected-count documentation and CI lower bound synchronized.

The single target framework is intentional for this runtime-specific experiment, not a default
target-framework policy for published libraries. Keep generated benchmark reports and build output
out of source control.
