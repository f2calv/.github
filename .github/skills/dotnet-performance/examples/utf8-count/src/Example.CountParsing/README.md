# Example.CountParsing

A source-only .NET 10 library for parsing UTF-8 counts without first allocating a decoded string.
It is a synthetic example, not a published NuGet package.

## Installation

Add a project reference from an existing .NET 10 consumer:

```console
dotnet add <consumer.csproj> reference <example-root>/src/Example.CountParsing/Example.CountParsing.csproj
```

Replace the paths with the actual consumer and downloaded example locations. The library has no
third-party runtime packages, configuration, service registrations or external service requirements.

## Usage

In a console application's entry point:

```csharp
using Example.CountParsing;

if (!CountParser.TryParse("123"u8, out var count))
    throw new FormatException("The sample count could not be parsed.");

Console.WriteLine(count);
```

The example prints `123`. [CountParser](./CountParser.cs) accepts a `ReadOnlySpan<byte>` and returns
`false` with a zero output on parse failure. Use the return value: a valid zero is not failure.

## Behavior and Limits

Parsing follows .NET's `NumberStyles.None` semantics with invariant culture and the `Int32` range.
Empty input, overflow, signs, whitespace and decimal separators are rejected. This is not a strict
wire-grammar validator: it preserves framework behavior, including accepted trailing NUL bytes.
Add separately specified protocol validation when a consumer requires a stricter grammar.

The API does not allocate a decoded string. That does not imply an entire caller is allocation-free:
creating the input byte array, logging or copying buffers can allocate. The included benchmark
measures already-available bytes, not network I/O or end-to-end throughput.

## Development

From the example root, after approval to run tests:

```console
dotnet test --project src/Example.CountParsing.Tests/Example.CountParsing.Tests.csproj --configuration Release
```

The [tests](../Example.CountParsing.Tests/Tests/Unit/CountParserTests.cs) compare valid, invalid,
overflow and byte-level cases against the original decode-then-parse behavior.
The [benchmark project](../Example.CountParsing.Benchmarks/README.md) compares that baseline with
direct UTF-8 parsing and an unnecessary-copy variant.
