# Example.HttpContract.Tests

Black-box HTTP tests for caller-supplied local comparison artifacts. One suite runs against the
managed controller baseline and either the managed or published native Minimal executable.
Each case starts a fresh loopback process and disposes it; no remote services or credentials are used.

The project is an xUnit v3 4.0.2 Microsoft.Testing.Platform executable. It has no project references.
Supply `EXAMPLE_CONTROLLER_PATH` and `EXAMPLE_MINIMAL_PATH` as absolute paths to built artifacts;
missing or nonexistent artifacts fail rather than silently skipping a required comparison.
See the [build and test commands](../../README.md).

## Tests

| Method | Methods | Expanded cases | Contract |
| --- | --- | --- | --- |
| `ReadWidget` | 1 | 2 | Status, JSON media type and DTO values |
| `MissingWidget` | 1 | 4 | Lookup and content absence |
| `CreateWidget` | 1 | 2 | Creation, named Location and following the created resource |
| `InvalidWidget` | 1 | 4 | Empty/null names, validation body and problem media type |
| `DuplicateWidget` | 1 | 2 | Conflict status, title and problem media type |
| `StreamWidget` | 1 | 2 | Attachment headers and fixed synthetic bytes |
| `DisabledWidgets` | 1 | 2 | Absent feature route without a DI failure |
| Total | 7 | 18 | 9 cases per adapter |

All cases have `Category=Integration` because they reach locally started application processes.
Observed managed result on 2026-11-07: 18 passed, 0 failed, 0 skipped. No native cases have run.

## Skipped Tests

There are no declared skip conditions and no skipped cases. A missing native artifact is a blocked
separate execution, not a passing or skipped native test run.

## Layout

```text
Example.HttpContract.Tests/
  Integration/
    HttpContractTests.cs
    TestBase.cs
```

No unit tests exist in this initial slice. See the [comparison limits](../../README.md#evidence-and-limits)
before treating this HTTP suite as coverage for all Native AOT gates.
