using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Example.HttpContract.Tests.Integration;

/// <summary>The same black-box contracts run against managed MVC and managed or native Minimal APIs.</summary>
[Trait("Category", "Integration")]
public sealed class HttpContractTests : TestBase
{
    /// <summary>Checks startup crashes report drained stderr and exit status without exposing local paths.</summary>
    [Fact]
    public async Task StartupFailureDiagnostics()
    {
        var directory = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "synthetic-invalid-fixture.dll");
        var previousPath = Environment.GetEnvironmentVariable("EXAMPLE_MINIMAL_PATH");
        try
        {
            await File.WriteAllTextAsync(path, "synthetic-invalid-fixture", TestContext.Current.CancellationToken);
            Environment.SetEnvironmentVariable("EXAMPLE_MINIMAL_PATH", path);
            var failure = await Assert.ThrowsAsync<Xunit.Sdk.FailException>(() => StartHostAsync("Minimal"));
            Assert.Contains("Exit status:", failure.Message);
            Assert.DoesNotContain("still running", failure.Message);
            Assert.Contains("stderr:", failure.Message);
            Assert.DoesNotContain("stderr: <empty>", failure.Message);
            Assert.DoesNotContain(directory, failure.Message);
        }
        finally
        {
            Environment.SetEnvironmentVariable("EXAMPLE_MINIMAL_PATH", previousPath);
            await DisposeAsync();
            Directory.Delete(directory, recursive: true);
        }
    }

    /// <summary>Checks generated DTO JSON for the seeded widget.</summary>
    [Theory]
    [InlineData("Controller")]
    [InlineData("Minimal")]
    public async Task ReadWidget(string host)
    {
        var client = await StartHostAsync(host);
        using var response = await client.GetAsync("/api/v1/widgets/1", TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
        Assert.Equal(1, json.RootElement.GetProperty("id").GetInt32());
        Assert.Equal("example-widget", json.RootElement.GetProperty("name").GetString());
    }

    /// <summary>Checks both absent-widget read contracts.</summary>
    [Theory]
    [InlineData("Controller", "99")]
    [InlineData("Minimal", "99")]
    [InlineData("Controller", "99/content")]
    [InlineData("Minimal", "99/content")]
    public async Task MissingWidget(string host, string suffix)
    {
        var client = await StartHostAsync(host);
        using var response = await client.GetAsync($"/api/v1/widgets/{suffix}", TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    /// <summary>Checks the named route's Location header resolves to the created resource.</summary>
    [Theory]
    [InlineData("Controller")]
    [InlineData("Minimal")]
    public async Task CreateWidget(string host)
    {
        var client = await StartHostAsync(host);
        using var response = await client.PostAsJsonAsync("/api/v1/widgets", new { name = "created-widget" }, TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal("/api/v1/widgets/2", response.Headers.Location?.AbsolutePath);
        using var created = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
        using var fetched = await client.GetAsync(response.Headers.Location, TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.OK, fetched.StatusCode);
        using var read = JsonDocument.Parse(await fetched.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
        Assert.Equal(created.RootElement.GetProperty("id").GetInt32(), read.RootElement.GetProperty("id").GetInt32());
        Assert.Equal("created-widget", read.RootElement.GetProperty("name").GetString());
    }

    /// <summary>Checks service-owned validation is mapped to problem JSON.</summary>
    [Theory]
    [InlineData("Controller", "")]
    [InlineData("Minimal", "")]
    [InlineData("Controller", null)]
    [InlineData("Minimal", null)]
    public async Task InvalidWidget(string host, string? name)
    {
        var client = await StartHostAsync(host);
        using var response = await client.PostAsJsonAsync("/api/v1/widgets", new { name }, TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
        Assert.Equal(400, json.RootElement.GetProperty("status").GetInt32());
        Assert.Equal("A name is required.", Assert.Single(json.RootElement.GetProperty("errors").GetProperty("name").EnumerateArray()).GetString());
    }

    /// <summary>Checks the bounded conflict result and its problem content type.</summary>
    [Theory]
    [InlineData("Controller")]
    [InlineData("Minimal")]
    public async Task DuplicateWidget(string host)
    {
        var client = await StartHostAsync(host);
        using var response = await client.PostAsJsonAsync("/api/v1/widgets", new { name = "example-widget" }, TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
        Assert.Equal(409, json.RootElement.GetProperty("status").GetInt32());
        Assert.Equal("Widget already exists.", json.RootElement.GetProperty("title").GetString());
    }

    /// <summary>Checks synthetic streaming headers and bytes.</summary>
    [Theory]
    [InlineData("Controller")]
    [InlineData("Minimal")]
    public async Task StreamWidget(string host)
    {
        var client = await StartHostAsync(host);
        using var response = await client.GetAsync("/api/v1/widgets/1/content", HttpCompletionOption.ResponseHeadersRead, TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/octet-stream", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal("attachment", response.Content.Headers.ContentDisposition?.DispositionType);
        Assert.Equal("widget.txt", response.Content.Headers.ContentDisposition?.FileNameStar);
        Assert.Equal("synthetic-widget-content", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
    }

    /// <summary>Checks disabling the feature removes routes rather than causing a DI failure.</summary>
    [Theory]
    [InlineData("Controller")]
    [InlineData("Minimal")]
    public async Task DisabledWidgets(string host)
    {
        var client = await StartHostAsync(host, disableWidgets: true);
        using var response = await client.GetAsync("/api/v1/widgets/1", TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
