# Example.CountParsing.Tests

Credential-free xUnit v3 tests on Microsoft.Testing.Platform for the UTF-8 count parser.
All cases are self-contained under `Tests/Unit`; no integration suite or external service is used.

## Run

From the example root, with test approval:

```console
dotnet test --project src/Example.CountParsing.Tests/Example.CountParsing.Tests.csproj --configuration Release --filter-trait "Category=Parsing"
```

The fixture requires a stable .NET 10 SDK and the declared package restore. Expected execution is
16 cases with no skips: 14 theory rows plus malformed UTF-8 and BOM checks.

## Coverage

| Cases | Contract |
| --- | --- |
| Zero, leading zeros, ordinary count and maximum integer | Accepted with the expected count |
| Empty, overflow, signs, whitespace, decimal, text and non-ASCII digit | Rejected with zero output |
| Trailing NUL | Framework-compatible acceptance, not strict protocol validation |
| Malformed bytes and BOM | Rejected without decoding an application string |

The theory also compares the direct parse with the original invariant string parse.
These tests prove correctness for the listed cases, not performance; use the separate benchmark
project for timing and allocation evidence.
