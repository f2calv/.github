using System.Diagnostics;

namespace Example.HttpContract.Tests.Integration;

/// <summary>Starts only caller-supplied local fixture artifacts on dynamic loopback ports.</summary>
public abstract class TestBase : IAsyncDisposable
{
    private readonly List<Process> _processes = [];
    private readonly List<HttpClient> _clients = [];

    /// <summary>Starts a fresh fixture process and returns its bounded loopback client.</summary>
    protected async Task<HttpClient> StartHostAsync(string host, bool disableWidgets = false)
    {
        var variable = host == "Controller" ? "EXAMPLE_CONTROLLER_PATH" : "EXAMPLE_MINIMAL_PATH";
        var path = Environment.GetEnvironmentVariable(variable);
        Assert.False(string.IsNullOrWhiteSpace(path), $"Set {variable} to the local fixture artifact before testing.");
        Assert.True(File.Exists(path), $"The artifact supplied through {variable} must exist.");
        var startInfo = new ProcessStartInfo
        {
            FileName = path.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) ? "dotnet" : path,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(Path.GetFullPath(path))!
        };
        if (path.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            startInfo.ArgumentList.Add(path);
        }
        startInfo.ArgumentList.Add("--urls");
        startInfo.ArgumentList.Add("http://127.0.0.1:0");
        if (disableWidgets)
        {
            startInfo.ArgumentList.Add("--disable-widgets");
        }
        var process = Process.Start(startInfo);
        Assert.NotNull(process);
        _processes.Add(process);
        using var startupDeadline = CancellationTokenSource.CreateLinkedTokenSource(TestContext.Current.CancellationToken);
        startupDeadline.CancelAfter(TimeSpan.FromSeconds(30));
        var address = await process.StandardOutput.ReadLineAsync(startupDeadline.Token);
        Assert.True(Uri.TryCreate(address, UriKind.Absolute, out var uri), "The fixture must emit its bound address after startup.");
        Assert.Equal("127.0.0.1", uri.Host);
        var client = new HttpClient { BaseAddress = uri, Timeout = TimeSpan.FromSeconds(10) };
        _clients.Add(client);
        return client;
    }

    /// <summary>Disposes clients and terminates all fixture processes, including after a failed assertion.</summary>
    public async ValueTask DisposeAsync()
    {
        foreach (var client in _clients)
        {
            client.Dispose();
        }
        foreach (var process in _processes)
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync();
                }
            }
            finally
            {
                process.Dispose();
            }
        }
        GC.SuppressFinalize(this);
    }
}
