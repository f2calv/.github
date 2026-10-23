using System.Globalization;
using System.Text;

namespace Example.CountParsing.Tests.Tests.Unit;

/// <summary>Checks the parsing contract and equivalence with decoded invariant parsing.</summary>
[Trait("Category", "Parsing")]
public sealed class CountParserTests
{
    [Theory]
    [InlineData("0", true, 0)]
    [InlineData("00042", true, 42)]
    [InlineData("123456789", true, 123456789)]
    [InlineData("2147483647", true, int.MaxValue)]
    [InlineData("2147483648", false, 0)]
    [InlineData("", false, 0)]
    [InlineData("+1", false, 0)]
    [InlineData("-1", false, 0)]
    [InlineData(" 1", false, 0)]
    [InlineData("1 ", false, 0)]
    [InlineData("1.0", false, 0)]
    [InlineData("invalid", false, 0)]
    [InlineData("\u0661", false, 0)]
    [InlineData("1\0", true, 1)]
    public void ParseCount(string input, bool expectedSuccess, int expectedCount)
    {
        var bytes = Encoding.UTF8.GetBytes(input);
        Assert.Equal(expectedSuccess, CountParser.TryParse(bytes, out var count));
        Assert.Equal(expectedCount, count);
        Assert.Equal(expectedSuccess, int.TryParse(input, NumberStyles.None,
            CultureInfo.InvariantCulture, out var baseline));
        Assert.Equal(baseline, count);
    }

    [Fact]
    public void RejectMalformedUtf8()
    {
        byte[] input = [0xc3, 0x28];
        Assert.False(CountParser.TryParse(input, out var count));
        Assert.Equal(0, count);
        Assert.False(int.TryParse(Encoding.UTF8.GetString(input), NumberStyles.None,
            CultureInfo.InvariantCulture, out var baseline));
        Assert.Equal(baseline, count);
    }

    [Fact]
    public void RejectBom()
    {
        byte[] input = [0xef, 0xbb, 0xbf, 0x31];
        Assert.False(CountParser.TryParse(input, out var count));
        Assert.Equal(0, count);
    }
}
