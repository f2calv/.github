namespace Example.CountParsing;

/// <summary>Parses a UTF-8 count using the framework's invariant, unsigned decimal parsing rules.</summary>
public static class CountParser
{
    /// <summary>Attempts parsing without decoding the input into a managed string.</summary>
    /// <param name="input">The UTF-8 bytes to parse.</param>
    /// <param name="count">The parsed nonnegative integer, or zero when parsing fails.</param>
    /// <returns>Whether the input represents a value accepted by invariant NumberStyles.None parsing.</returns>
    public static bool TryParse(ReadOnlySpan<byte> input, out int count) =>
        int.TryParse(input, NumberStyles.None, CultureInfo.InvariantCulture, out count);
}
