# Example.CountParsing.Benchmarks

A BenchmarkDotNet comparison of decoded-string, direct UTF-8 and copy-then-parse paths for the
same nine-byte count. It is a local measurement fixture, not an application load test.

## Run

From the example root, with benchmark approval:

On Windows use a short fixture location before building. A short `--artifacts` argument alone does
not shorten BenchmarkDotNet's generated build tree under `bin/`. If an otherwise successful project
fails there with MSB3030/missing generated assemblies, retry the whole fixture from a short path;
do not copy DLLs by hand or switch to in-process execution merely to obtain numbers.

```console
dotnet run --configuration Release --project src/Example.CountParsing.Benchmarks -- --filter "*CountParsingBenchmarks*" --artifacts <temporary-output-directory>
```

Use a stable .NET 10 SDK, no attached debugger, and the pinned package versions in the example's
central package file. The job uses two process launches, three warmups and five measured iterations
per launch and preserves the workstation's existing power plan. Memory diagnostics are enabled;
input creation and the correctness guard are outside
the timed operations.

The benchmark class is intentionally unsealed because BenchmarkDotNet derives its generated harness
from it. The entry point returns a nonzero exit code for validation errors or incomplete results;
still verify the report contains the expected methods rather than relying on process exit alone.

All methods return the parsed integer, keeping their useful result observable. The input is already
UTF-8 and remains unchanged. Changing input construction, lifetime or distribution changes the
question being measured.

## Interpret Results

Compare mean/error, variation between launches and bytes allocated per operation. Do not infer
end-to-end application speedup or impose nanosecond thresholds on shared CI hardware.
Reject the extra-copy candidate when it adds allocations without a useful measured gain over
direct parsing.

Raw reports can contain machine names and local paths. Keep them local; publish only reviewed
measurements and non-sensitive conditions. Repeat with the real application's input distribution
and runtime before adopting a change.
