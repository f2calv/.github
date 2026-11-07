using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace Example.HttpContract.Tests.Integration;

/// <summary>Starts only caller-supplied local fixture artifacts on dynamic loopback ports.</summary>
public abstract class TestBase : IAsyncDisposable
{
    private readonly List<(Process Process, CancellationTokenSource DrainCancellation, Task<string> StandardError)> _processes = [];
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
        var drainCancellation = new CancellationTokenSource();
        var standardError = DrainStandardErrorAsync(process.StandardError, drainCancellation.Token);
        _processes.Add((process, drainCancellation, standardError));
        using var startupDeadline = CancellationTokenSource.CreateLinkedTokenSource(TestContext.Current.CancellationToken);
        startupDeadline.CancelAfter(TimeSpan.FromSeconds(30));
        string? address = null;
        try
        {
            address = await process.StandardOutput.ReadLineAsync(startupDeadline.Token);
        }
        catch (OperationCanceledException) when (!TestContext.Current.CancellationToken.IsCancellationRequested)
        {
        }
        if (!Uri.TryCreate(address, UriKind.Absolute, out var uri) || uri.Host != "127.0.0.1")
        {
            try
            {
                await process.WaitForExitAsync(startupDeadline.Token);
                await standardError.WaitAsync(startupDeadline.Token);
            }
            catch (OperationCanceledException) when (!TestContext.Current.CancellationToken.IsCancellationRequested)
            {
                await drainCancellation.CancelAsync();
            }
            var diagnostics = await standardError;
            diagnostics = Regex.Replace(diagnostics, @"(?:[A-Za-z]:[\\/]|(?<![\w:])/(?!/))[^\r\n]*", "[path]", RegexOptions.None, TimeSpan.FromSeconds(1));
            var exitStatus = process.HasExited ? $"{process.ExitCode}" : "still running (startup deadline elapsed)";
            Assert.Fail($"The fixture must emit its loopback address after startup. Exit status: {exitStatus}; stderr: {(diagnostics.Length == 0 ? "<empty>" : diagnostics)}");
        }
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
        foreach (var (process, drainCancellation, standardError) in _processes)
        {
            try
            {
                if (!process.HasExited)
                {
                    try
                    {
                        process.Kill(entireProcessTree: true);
                    }
                    catch (InvalidOperationException) when (process.HasExited)
                    {
                    }
                    await process.WaitForExitAsync(CancellationToken.None);
                }
            }
            finally
            {
                await drainCancellation.CancelAsync();
                try
                {
                    await standardError;
                }
                finally
                {
                    drainCancellation.Dispose();
                    process.Dispose();
                }
            }
        }
        _clients.Clear();
        _processes.Clear();
        GC.SuppressFinalize(this);
    }

    private static async Task<string> DrainStandardErrorAsync(StreamReader reader, CancellationToken cancellationToken)
    {
        const int diagnosticLimit = 4096;
        var diagnostics = new StringBuilder();
        var buffer = new char[1024];
        try
        {
            int charactersRead;
            while ((charactersRead = await reader.ReadAsync(buffer.AsMemory(), cancellationToken)) != 0)
            {
                diagnostics.Append(buffer, 0, Math.Min(charactersRead, diagnosticLimit - diagnostics.Length));
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        return diagnostics.ToString();
    }
}
