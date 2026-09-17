#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Creates a GitHub repository and applies the standard repository baseline.
.DESCRIPTION
    Creates a repository with an initialized default branch, reconciles its
    GitHub settings, clones it under the configured root, and optionally adds
    the clone to the active VS Code workspace.
.PARAMETER Name
    Name of the repository to create.
.PARAMETER Owner
    GitHub owner. Defaults to the authenticated GitHub account.
.PARAMETER Description
    Optional repository description.
.PARAMETER Visibility
    Public or private repository visibility.
.PARAMETER TemplateRepository
    Optional template repository in owner/name format.
.PARAMETER CloneRoot
    Parent directory for the local clone.
.PARAMETER NoClone
    Creates and configures the repository without cloning it.
.PARAMETER AddToWorkspace
    Adds the local clone to the active VS Code multi-root workspace.
.PARAMETER Resume
    Continues setup when the remote repository or expected local clone exists.
.EXAMPLE
    ./.scripts/New-GitHubRepository.ps1 -Name example -Description 'Example repository'
.EXAMPLE
    ./.scripts/New-GitHubRepository.ps1 -Name example -TemplateRepository f2calv/template-dotnet -AddToWorkspace
.NOTES
    Requires GitHub CLI authentication with repository creation access.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Owner,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$Description = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Public', 'Private')]
    [string]$Visibility = 'Public',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$TemplateRepository,

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$CloneRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [Parameter(Mandatory = $false)]
    [switch]$NoClone,

    [Parameter(Mandatory = $false)]
    [switch]$AddToWorkspace,

    [Parameter(Mandatory = $false)]
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'

#region Functions

function Invoke-NativeCommand {
    <#
    .SYNOPSIS
        Invokes a native executable and captures its output and exit code.
    .PARAMETER FileName
        Executable name or path.
    .PARAMETER Arguments
        Arguments passed to the executable.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments
    )

    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $FileName
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $StartInfo.UseShellExecute = $false

    foreach ($Argument in $Arguments) {
        $StartInfo.ArgumentList.Add($Argument)
    }

    $Process = [Diagnostics.Process]::Start($StartInfo)
    $StandardOutputTask = $Process.StandardOutput.ReadToEndAsync()
    $StandardErrorTask = $Process.StandardError.ReadToEndAsync()
    $Process.WaitForExit()
    $StandardOutput = $StandardOutputTask.GetAwaiter().GetResult()
    $StandardError = $StandardErrorTask.GetAwaiter().GetResult()

    [pscustomobject]@{
        ExitCode = $Process.ExitCode
        Output   = $StandardOutput.Trim()
        Error    = $StandardError.Trim()
    }
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw 'GitHub CLI (gh) is required.'
        }

        if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            throw 'PowerShell 7 (pwsh) is required.'
        }

        if (-not $NoClone -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw 'Git is required unless -NoClone is specified.'
        }

        if ($AddToWorkspace -and $NoClone) {
            throw '-AddToWorkspace requires a local clone. Remove -NoClone.'
        }

        if ($AddToWorkspace -and -not (Get-Command code -ErrorAction SilentlyContinue)) {
            throw 'VS Code CLI (code) is required for -AddToWorkspace.'
        }

        $BaselineScript = Join-Path `
            $PSScriptRoot `
            '../skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1'
        if (-not (Test-Path -LiteralPath $BaselineScript -PathType Leaf)) {
            throw "Repository baseline script was not found: $BaselineScript"
        }

        if (-not $Owner) {
            $Authentication = Invoke-NativeCommand -FileName 'gh' -Arguments @('api', 'user', '--jq', '.login')
            if ($Authentication.ExitCode -ne 0) {
                throw "GitHub authentication failed: $($Authentication.Error)"
            }
            $Owner = $Authentication.Output
        }

        $FullName = "$Owner/$Name"
        $ClonePath = Join-Path $CloneRoot $Name
        $RepositoryResponse = Invoke-NativeCommand -FileName 'gh' -Arguments @(
            'repo', 'view', $FullName, '--json', 'nameWithOwner')
        $RepositoryExists = $RepositoryResponse.ExitCode -eq 0
        $CloneExists = Test-Path -LiteralPath $ClonePath -PathType Container

        if ($RepositoryExists -and -not $Resume) {
            throw "Repository already exists: $FullName. Use -Resume to continue setup."
        }
        if ($CloneExists -and -not $Resume -and -not $NoClone) {
            throw "Clone path already exists: $ClonePath. Use -Resume to continue setup."
        }
        if ($Resume -and $CloneExists -and -not $NoClone -and -not $RepositoryExists) {
            throw "Cannot resume from $ClonePath because the remote repository does not exist: $FullName"
        }
        if ($Resume -and $CloneExists -and -not $NoClone) {
            $OriginResponse = Invoke-NativeCommand -FileName 'git' -Arguments @(
                '-C', $ClonePath, 'remote', 'get-url', 'origin')
            $EscapedOwner = [regex]::Escape($Owner)
            $EscapedName = [regex]::Escape($Name)
            $ExpectedOriginPattern = "^(?:https://github\.com/|git@github\.com:)$EscapedOwner/$EscapedName(?:\.git)?$"
            if ($OriginResponse.ExitCode -ne 0 -or $OriginResponse.Output -notmatch $ExpectedOriginPattern) {
                throw "Existing clone does not use $FullName as its GitHub origin: $ClonePath"
            }
        }

        if (-not $PSCmdlet.ShouldProcess($FullName, 'Create or resume GitHub repository setup')) {
            if (-not $RepositoryExists) {
                Write-Host "What if: create $Visibility repository $FullName"
            }
            Write-Host "What if: apply repository baseline to $FullName"
            if (-not $NoClone -and -not $CloneExists) {
                Write-Host "What if: clone $FullName to $ClonePath"
            }
            if ($AddToWorkspace) {
                Write-Host "What if: add $ClonePath to the active VS Code workspace"
            }
            exit 0
        }

        if (-not $RepositoryExists) {
            $CreateArguments = @('repo', 'create', $FullName)
            $CreateArguments += if ($Visibility -eq 'Public') { '--public' } else { '--private' }
            if ($Description) {
                $CreateArguments += @('--description', $Description)
            }
            if ($TemplateRepository) {
                $CreateArguments += @('--template', $TemplateRepository)
            }
            else {
                $CreateArguments += '--add-readme'
            }

            $CreateResponse = Invoke-NativeCommand -FileName 'gh' -Arguments $CreateArguments
            if ($CreateResponse.ExitCode -ne 0) {
                throw "Repository creation failed: $($CreateResponse.Error)"
            }
        }

        $BaselineResponse = Invoke-NativeCommand -FileName 'pwsh' -Arguments @(
            '-NoProfile',
            '-File', $BaselineScript,
            '-Repository', $FullName,
            '-Mode', 'Apply')
        if ($BaselineResponse.ExitCode -ne 0) {
            throw "Repository was created, but baseline reconciliation failed for $FullName`: $($BaselineResponse.Error)"
        }

        if (-not $NoClone -and -not $CloneExists) {
            $CloneResponse = Invoke-NativeCommand -FileName 'gh' -Arguments @(
                'repo', 'clone', $FullName, $ClonePath)
            if ($CloneResponse.ExitCode -ne 0) {
                throw "Repository was created and configured, but cloning failed: $($CloneResponse.Error)"
            }
        }

        if ($AddToWorkspace) {
            $WorkspaceResponse = Invoke-NativeCommand -FileName 'code' -Arguments @('--add', $ClonePath)
            if ($WorkspaceResponse.ExitCode -ne 0) {
                throw "Repository was created, configured, and cloned, but workspace attachment failed: $($WorkspaceResponse.Error)"
            }
        }

        Write-Host "Created and configured https://github.com/$FullName" -ForegroundColor Green
        if (-not $NoClone) {
            Write-Host "Clone: $ClonePath"
        }
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "New repository setup failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
