#Requires -Version 7.4

# Helpers dot-sourced by the azure-reporting scripts and tested through them.

# Pass-through wrapper so tests can mock the Azure CLI; stderr warnings never reach the JSON.
function Invoke-AzCli {
    $all = @(& az @args 2>&1)
    $stdout = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    if ($LASTEXITCODE -ne 0) {
        $stderr = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join ' '
        throw "az $($args[0]) $($args[1]) failed: $stderr"
    }
    return ($stdout -join "`n")
}

function Test-ThrottledError {
    [CmdletBinding()][OutputType([bool])]
    param([Parameter(Mandatory)][string]$Message)
    return $Message -match '\b429\b|Too Many Requests'
}

function Invoke-WithThrottleRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [ValidateRange(1, 10)][int]$MaxAttempts = 5,
        [ValidateRange(0, 600)][int]$InitialDelaySeconds = 10,
        [scriptblock]$Sleep = { param($Seconds) Start-Sleep -Seconds $Seconds }
    )
    for ($attempt = 1; ; $attempt++) {
        try {
            return & $Operation
        }
        catch {
            if ($attempt -ge $MaxAttempts -or -not (Test-ThrottledError -Message "$_")) { throw }
            $delay = $InitialDelaySeconds * [math]::Pow(2, $attempt - 1)
            Write-Verbose "Throttled; retrying in $delay seconds (attempt $attempt of $MaxAttempts)."
            & $Sleep $delay
        }
    }
}
