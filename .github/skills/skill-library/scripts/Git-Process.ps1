#!/usr/bin/env pwsh
#Requires -Version 7.4

#region Functions
function Invoke-LibraryProcess {
    param(
        [string]$Executable, [string[]]$Arguments,
        [byte[]]$InputBytes, [System.Collections.IDictionary]$Environment = @{}
    )
    $Start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $Start.UseShellExecute = $false
    $Start.RedirectStandardOutput = $true
    $Start.RedirectStandardError = $true
    $Start.RedirectStandardInput = $PSBoundParameters.ContainsKey('InputBytes')
    foreach ($Key in @($Start.Environment.Keys)) {
        if ($Key.StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase)) { [void]$Start.Environment.Remove($Key) }
    }
    $Start.Environment['GIT_NO_REPLACE_OBJECTS'] = '1'
    $Start.Environment['GIT_NO_LAZY_FETCH'] = '1'
    $Start.Environment['GIT_OPTIONAL_LOCKS'] = '0'
    $Start.Environment['GIT_ALLOW_PROTOCOL'] = ''
    $Start.Environment['GIT_TERMINAL_PROMPT'] = '0'
    $Start.Environment['PYTHONDONTWRITEBYTECODE'] = '1'
    foreach ($Key in $Environment.Keys) { $Start.Environment[$Key] = $Environment[$Key] }
    foreach ($Argument in $Arguments) { $Start.ArgumentList.Add($Argument) }
    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $Start
    $Buffer = [IO.MemoryStream]::new()
    try {
        [void]$Process.Start()
        $OutputTask = $Process.StandardOutput.BaseStream.CopyToAsync($Buffer)
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        if ($Start.RedirectStandardInput) {
            try { $Process.StandardInput.BaseStream.Write($InputBytes, 0, $InputBytes.Length) }
            finally { $Process.StandardInput.Close() }
        }
        $Process.WaitForExit()
        [void]$OutputTask.GetAwaiter().GetResult()
        $ErrorText = $ErrorTask.GetAwaiter().GetResult()
        return [pscustomobject]@{ Bytes = $Buffer.ToArray(); Error = $ErrorText; ExitCode = $Process.ExitCode }
    }
    finally { $Buffer.Dispose(); $Process.Dispose() }
}

function Invoke-LibraryGit {
    param(
        [string]$Root, [string[]]$Arguments,
        [byte[]]$InputBytes, [System.Collections.IDictionary]$Environment = @{}
    )
    $Executable = (Get-Command git -CommandType Application -TotalCount 1).Source
    $Parameters = @{
        Executable = $Executable
        Arguments = @('--no-optional-locks', '-c', "safe.directory=$Root", '-c', 'core.fsmonitor=false', '-C', $Root) + $Arguments
        Environment = $Environment
    }
    if ($PSBoundParameters.ContainsKey('InputBytes')) { $Parameters['InputBytes'] = $InputBytes }
    Invoke-LibraryProcess @Parameters
}
#endregion
