using System.Globalization;
using System.Text;

namespace Example.CountParsing.Benchmarks;

/// <summary>Compares parsing the same already-buffered UTF-8 count through three allocation paths.</summary>
[MemoryDiagnoser]
// BenchmarkDotNet derives its generated harness from this type.
public class CountParsingBenchmarks
{
    private readonly byte[] _input = "123456789"u8.ToArray();

    /// <summary>Checks equal observable results before any timing is collected.</summary>
    [GlobalSetup]
    public void VerifyResults()
    {
        if (DecodeThenParse() != 123456789 || ParseUtf8() != 123456789 || CopyThenParse() != 123456789)
            throw new InvalidOperationException("The benchmark variants produced different results.");
    }

    /// <summary>Models the original decoded-string allocation followed by invariant parsing.</summary>
    [Benchmark(Baseline = true)]
    public int DecodeThenParse() =>
        int.TryParse(Encoding.UTF8.GetString(_input), NumberStyles.None,
            CultureInfo.InvariantCulture, out var count) ? count : -1;

    /// <summary>Parses the existing buffer directly without a decoded string.</summary>
    [Benchmark]
    public int ParseUtf8() =>
        CountParser.TryParse(_input, out var count) ? count : -1;

    /// <summary>Demonstrates the extra allocation from copying an already suitable buffer.</summary>
    [Benchmark]
    public int CopyThenParse() =>
        CountParser.TryParse(_input.ToArray(), out var count) ? count : -1;
}
