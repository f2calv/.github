#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Audits or applies the standard settings for GitHub repositories.
.DESCRIPTION
    Reconciles repository cleanup, GitHub Actions permissions, Dependabot,
    secret protection, and default-branch pull request rules. The script can
    target specific repositories or every active, owned, non-fork repository.
.PARAMETER Repository
    One or more repositories in owner/name format. Names without an owner use
    the authenticated GitHub account.
.PARAMETER AllOwned
    Targets every active, owned, non-fork repository.
.PARAMETER Mode
    Audit reports drift without changing GitHub. Apply reconciles drift.
.PARAMETER PolicyPath
    Path to the JSON policy document.
.PARAMETER OutputPath
    Optional path for the complete JSON result.
.EXAMPLE
    ./.scripts/Set-RepositoryBaseline.ps1 -Repository f2calv/example -Mode Apply
.EXAMPLE
    ./.scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Audit
.EXAMPLE
    ./.scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Apply -WhatIf
.NOTES
    Requires GitHub CLI authentication with repository administration access.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Repository,

    [Parameter(Mandatory = $false)]
    [switch]$AllOwned,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Audit', 'Apply')]
    [string]$Mode = 'Audit',

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$PolicyPath = (Join-Path $PSScriptRoot 'repository-baseline.json'),

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

#region Functions

function Invoke-GhCommand {
    <#
    .SYNOPSIS
        Invokes GitHub CLI without exposing expected HTTP errors to PowerShell.
    .PARAMETER Arguments
        Arguments passed to the GitHub CLI executable.
    .PARAMETER StandardInput
        Optional content written to the process standard input stream.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$StandardInput
    )

    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = 'gh'
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $StartInfo.RedirectStandardInput = $PSBoundParameters.ContainsKey('StandardInput')
    $StartInfo.UseShellExecute = $false

    foreach ($Argument in $Arguments) {
        $StartInfo.ArgumentList.Add($Argument)
    }

    $Process = [Diagnostics.Process]::Start($StartInfo)
    if ($PSBoundParameters.ContainsKey('StandardInput')) {
        $Process.StandardInput.Write($StandardInput)
        $Process.StandardInput.Close()
    }

    $StandardOutputTask = $Process.StandardOutput.ReadToEndAsync()
    $StandardErrorTask = $Process.StandardError.ReadToEndAsync()
    $Process.WaitForExit()
    $StandardOutput = $StandardOutputTask.GetAwaiter().GetResult()
    $StandardError = $StandardErrorTask.GetAwaiter().GetResult()

    [pscustomobject]@{
        ExitCode = $Process.ExitCode
        Output   = $StandardOutput
        Error    = $StandardError.Trim()
    }
}

function ConvertFrom-GhResponse {
    <#
    .SYNOPSIS
        Converts a successful GitHub CLI JSON response.
    .PARAMETER Response
        Response returned by Invoke-GhCommand.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Response
    )

    if ($Response.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($Response.Output)) {
        return $null
    }

    $Response.Output | ConvertFrom-Json -Depth 100
}

function Get-FailureStatus {
    <#
    .SYNOPSIS
        Classifies GitHub feature availability failures.
    .PARAMETER ErrorText
        GitHub CLI standard error text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ErrorText
    )

    if ($ErrorText -match 'Upgrade to GitHub Pro|not available for this repository|Advanced Security must be enabled') {
        return 'PlanGated'
    }

    return 'Failed'
}

function Add-BaselineResult {
    <#
    .SYNOPSIS
        Adds one setting result to the result collection.
    .PARAMETER Results
        Mutable result collection.
    .PARAMETER RepositoryName
        Repository in owner/name format.
    .PARAMETER Setting
        Baseline setting identifier.
    .PARAMETER Status
        Reconciliation status.
    .PARAMETER Detail
        Optional explanatory detail.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Collections.Generic.List[object]]$Results,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryName,

        [Parameter(Mandatory = $true)]
        [string]$Setting,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Compliant', 'Changed', 'Drift', 'PlanGated', 'Failed', 'WhatIf')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Detail = ''
    )

    $Results.Add([pscustomobject]@{
            Repository = $RepositoryName
            Setting    = $Setting
            Status     = $Status
            Detail     = $Detail
        })
}

function Invoke-GhMutation {
    <#
    .SYNOPSIS
        Sends a JSON mutation through GitHub CLI.
    .PARAMETER Method
        HTTP method for the API request.
    .PARAMETER Path
        GitHub REST API path.
    .PARAMETER Body
        Optional object serialized as the request body.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DELETE', 'PATCH', 'POST', 'PUT')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [object]$Body
    )

    $Arguments = @('api', '--method', $Method, $Path)
    if ($PSBoundParameters.ContainsKey('Body')) {
        $Arguments += @('--input', '-')
        $Json = $Body | ConvertTo-Json -Depth 30 -Compress
        return Invoke-GhCommand -Arguments $Arguments -StandardInput $Json
    }

    Invoke-GhCommand -Arguments $Arguments
}

function Get-RepositoryTargets {
    <#
    .SYNOPSIS
        Resolves requested repository names into owner/name references.
    .PARAMETER RepositoryNames
        Explicit repository names.
    .PARAMETER IncludeAllOwned
        Discovers active, owned, non-fork repositories.
    .PARAMETER AuthenticatedOwner
        Authenticated GitHub login used for unqualified names.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$RepositoryNames,

        [Parameter(Mandatory = $true)]
        [bool]$IncludeAllOwned,

        [Parameter(Mandatory = $true)]
        [string]$AuthenticatedOwner
    )

    if ($IncludeAllOwned) {
        $Response = Invoke-GhCommand -Arguments @(
            'api',
            '--paginate',
            '--slurp',
            'user/repos?affiliation=owner&per_page=100&sort=full_name')
        if ($Response.ExitCode -ne 0) {
            throw "Unable to list owned repositories: $($Response.Error)"
        }

        $Pages = @(ConvertFrom-GhResponse -Response $Response)
        return @($Pages |
            ForEach-Object { $_ } |
            Where-Object {
                -not $_.fork -and
                -not $_.archived -and
                -not $_.disabled -and
                $_.owner.login -eq $AuthenticatedOwner
            } |
            ForEach-Object { $_.full_name } |
            Sort-Object -Unique)
    }

    @($RepositoryNames | ForEach-Object {
            if ($_ -match '/') {
                $_
            }
            else {
                "$AuthenticatedOwner/$_"
            }
        } | Sort-Object -Unique)
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($AllOwned -eq [bool]$Repository) {
            throw 'Specify either -Repository or -AllOwned.'
        }

        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw 'GitHub CLI (gh) is required.'
        }

        $Authentication = Invoke-GhCommand -Arguments @('api', 'user')
        if ($Authentication.ExitCode -ne 0) {
            throw "GitHub authentication failed: $($Authentication.Error)"
        }

        $Owner = (ConvertFrom-GhResponse -Response $Authentication).login
        $Policy = Get-Content -Raw -LiteralPath $PolicyPath | ConvertFrom-Json -Depth 100
        $Targets = Get-RepositoryTargets `
            -RepositoryNames $Repository `
            -IncludeAllOwned $AllOwned.IsPresent `
            -AuthenticatedOwner $Owner
        $Results = [Collections.Generic.List[object]]::new()

        foreach ($FullName in $Targets) {
            $Parts = $FullName.Split('/', 2)
            if ($Parts.Count -ne 2) {
                throw "Invalid repository name: $FullName"
            }

            $RepositoryPath = "repos/$($Parts[0])/$($Parts[1])"
            $DetailResponse = Invoke-GhCommand -Arguments @('api', $RepositoryPath)
            if ($DetailResponse.ExitCode -ne 0) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'repository' -Status 'Failed' -Detail $DetailResponse.Error
                continue
            }

            $Detail = ConvertFrom-GhResponse -Response $DetailResponse

            if ($Detail.delete_branch_on_merge -eq $Policy.repository.deleteBranchOnMerge) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'delete_branch_on_merge' -Status 'Compliant'
            }
            elseif ($Mode -eq 'Audit') {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'delete_branch_on_merge' -Status 'Drift'
            }
            elseif ($PSCmdlet.ShouldProcess($FullName, 'Enable automatic deletion of merged branches')) {
                $Response = Invoke-GhMutation -Method PATCH -Path $RepositoryPath -Body @{
                    delete_branch_on_merge = $Policy.repository.deleteBranchOnMerge
                }
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'delete_branch_on_merge' `
                    -Status $(if ($Response.ExitCode -eq 0) { 'Changed' } else { 'Failed' }) `
                    -Detail $Response.Error
            }
            else {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'delete_branch_on_merge' -Status 'WhatIf'
            }

            $ActionsPath = "$RepositoryPath/actions/permissions/workflow"
            $ActionsResponse = Invoke-GhCommand -Arguments @('api', $ActionsPath)
            $Actions = ConvertFrom-GhResponse -Response $ActionsResponse
            $ActionsCompliant = $ActionsResponse.ExitCode -eq 0 -and
            $Actions.default_workflow_permissions -eq $Policy.actions.defaultWorkflowPermissions -and
            $Actions.can_approve_pull_request_reviews -eq $Policy.actions.canApprovePullRequestReviews

            if ($ActionsCompliant) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'actions_permissions' -Status 'Compliant'
            }
            elseif ($Mode -eq 'Audit') {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'actions_permissions' -Status 'Drift' -Detail $ActionsResponse.Error
            }
            elseif ($PSCmdlet.ShouldProcess($FullName, 'Set read-only GitHub Actions permissions')) {
                $Response = Invoke-GhMutation -Method PUT -Path $ActionsPath -Body @{
                    default_workflow_permissions     = $Policy.actions.defaultWorkflowPermissions
                    can_approve_pull_request_reviews = $Policy.actions.canApprovePullRequestReviews
                }
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'actions_permissions' `
                    -Status $(if ($Response.ExitCode -eq 0) { 'Changed' } else { 'Failed' }) `
                    -Detail $Response.Error
            }
            else {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'actions_permissions' -Status 'WhatIf'
            }

            $AlertsPath = "$RepositoryPath/vulnerability-alerts"
            $AlertsResponse = Invoke-GhCommand -Arguments @('api', $AlertsPath)
            if ($AlertsResponse.ExitCode -ne 0 -and $AlertsResponse.Error -notmatch '\bHTTP 404\b') {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_alerts' -Status 'Failed' -Detail $AlertsResponse.Error
                continue
            }
            $AlertsEnabled = $AlertsResponse.ExitCode -eq 0
            if ($AlertsEnabled -eq $Policy.security.dependabotAlerts) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_alerts' -Status 'Compliant'
            }
            elseif ($Mode -eq 'Audit') {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_alerts' -Status 'Drift'
            }
            elseif ($PSCmdlet.ShouldProcess($FullName, 'Reconcile Dependabot vulnerability alerts')) {
                $Method = if ($Policy.security.dependabotAlerts) { 'PUT' } else { 'DELETE' }
                $Response = Invoke-GhMutation -Method $Method -Path $AlertsPath
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_alerts' `
                    -Status $(if ($Response.ExitCode -eq 0) { 'Changed' } else { Get-FailureStatus $Response.Error }) `
                    -Detail $Response.Error
            }
            else {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_alerts' -Status 'WhatIf'
            }

            $SecurityUpdatesPath = "$RepositoryPath/automated-security-fixes"
            $SecurityUpdatesResponse = Invoke-GhCommand -Arguments @('api', $SecurityUpdatesPath)
            if ($SecurityUpdatesResponse.ExitCode -ne 0 -and $SecurityUpdatesResponse.Error -notmatch '\bHTTP 404\b') {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_security_updates' -Status 'Failed' -Detail $SecurityUpdatesResponse.Error
                continue
            }
            $SecurityUpdates = ConvertFrom-GhResponse -Response $SecurityUpdatesResponse
            $SecurityUpdatesEnabled = $SecurityUpdatesResponse.ExitCode -eq 0 -and $SecurityUpdates.enabled
            if ($SecurityUpdatesEnabled -eq $Policy.security.dependabotSecurityUpdates) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_security_updates' -Status 'Compliant'
            }
            elseif ($Mode -eq 'Audit') {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_security_updates' -Status 'Drift'
            }
            elseif ($PSCmdlet.ShouldProcess($FullName, 'Reconcile Dependabot security updates')) {
                $Method = if ($Policy.security.dependabotSecurityUpdates) { 'PUT' } else { 'DELETE' }
                $Response = Invoke-GhMutation -Method $Method -Path $SecurityUpdatesPath
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_security_updates' `
                    -Status $(if ($Response.ExitCode -eq 0) { 'Changed' } else { Get-FailureStatus $Response.Error }) `
                    -Detail $Response.Error
            }
            else {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'dependabot_security_updates' -Status 'WhatIf'
            }

            $SecretScanningEnabled = $Detail.security_and_analysis.secret_scanning.status -eq 'enabled'
            $PushProtectionEnabled = $Detail.security_and_analysis.secret_scanning_push_protection.status -eq 'enabled'
            $SecretScanningCompliant =
            $SecretScanningEnabled -eq $Policy.security.secretScanning -and
            $PushProtectionEnabled -eq $Policy.security.secretScanningPushProtection
            if ($SecretScanningCompliant) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'secret_protection' -Status 'Compliant'
            }
            elseif ($Policy.security.secretScanning -and
                $Detail.visibility -eq 'private' -and
                $null -eq $Detail.security_and_analysis.secret_scanning) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'secret_protection' -Status 'PlanGated' `
                    -Detail 'Secret protection is unavailable for this private repository on the current plan.'
            }
            elseif ($Mode -eq 'Audit') {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'secret_protection' -Status 'Drift'
            }
            elseif ($PSCmdlet.ShouldProcess($FullName, 'Reconcile secret scanning and push protection')) {
                $SecretScanningStatus = if ($Policy.security.secretScanning) { 'enabled' } else { 'disabled' }
                $PushProtectionStatus = if ($Policy.security.secretScanningPushProtection) { 'enabled' } else { 'disabled' }
                $Response = Invoke-GhMutation -Method PATCH -Path $RepositoryPath -Body @{
                    security_and_analysis = @{
                        secret_scanning                 = @{ status = $SecretScanningStatus }
                        secret_scanning_push_protection = @{ status = $PushProtectionStatus }
                    }
                }
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'secret_protection' `
                    -Status $(if ($Response.ExitCode -eq 0) { 'Changed' } else { Get-FailureStatus $Response.Error }) `
                    -Detail $Response.Error
            }
            else {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'secret_protection' -Status 'WhatIf'
            }

            $EncodedBranch = [Uri]::EscapeDataString($Detail.default_branch)
            $RulesPath = "$RepositoryPath/rules/branches/$EncodedBranch`?per_page=100"
            $RulesResponse = Invoke-GhCommand -Arguments @('api', '--paginate', '--slurp', $RulesPath)
            if ($RulesResponse.ExitCode -ne 0) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'default_branch_ruleset' `
                    -Status $(Get-FailureStatus $RulesResponse.Error) `
                    -Detail $RulesResponse.Error
                continue
            }

            $RulePages = @(ConvertFrom-GhResponse -Response $RulesResponse)
            $Rules = @($RulePages | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
            $PullRequestRule = $Rules | Where-Object type -eq 'pull_request' | Select-Object -First 1
            $RulesCompliant =
            @($Rules | Where-Object type -eq 'deletion').Count -gt 0 -and
            @($Rules | Where-Object type -eq 'non_fast_forward').Count -gt 0 -and
            $null -ne $PullRequestRule -and
            $PullRequestRule.parameters.required_review_thread_resolution

            if ($RulesCompliant) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'default_branch_ruleset' -Status 'Compliant'
                continue
            }

            if ($Mode -eq 'Audit') {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'default_branch_ruleset' -Status 'Drift'
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($FullName, 'Apply the default branch pull request ruleset')) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'default_branch_ruleset' -Status 'WhatIf'
                continue
            }

            $RulesetsPath = "$RepositoryPath/rulesets?includes_parents=false&per_page=100"
            $RulesetsResponse = Invoke-GhCommand -Arguments @('api', $RulesetsPath)
            if ($RulesetsResponse.ExitCode -ne 0) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'default_branch_ruleset' `
                    -Status $(Get-FailureStatus $RulesetsResponse.Error) `
                    -Detail $RulesetsResponse.Error
                continue
            }

            $ExistingRuleset = @(ConvertFrom-GhResponse -Response $RulesetsResponse) |
            Where-Object {
                $_.name -eq $Policy.ruleset.name -and
                $_.source_type -eq 'Repository' -and
                $_.source -eq $FullName
            } |
            Select-Object -First 1
            if ($null -eq $ExistingRuleset) {
                $Response = Invoke-GhMutation -Method POST -Path "$RepositoryPath/rulesets" -Body $Policy.ruleset
            }
            else {
                $Response = Invoke-GhMutation -Method PUT `
                    -Path "$RepositoryPath/rulesets/$($ExistingRuleset.id)" `
                    -Body $Policy.ruleset
            }

            Add-BaselineResult -Results $Results -RepositoryName $FullName `
                -Setting 'default_branch_ruleset' `
                -Status $(if ($Response.ExitCode -eq 0) { 'Changed' } else { Get-FailureStatus $Response.Error }) `
                -Detail $Response.Error
        }

        if ($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath, 'Write baseline result JSON')) {
            $OutputDirectory = Split-Path -Parent $OutputPath
            if ($OutputDirectory) {
                New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
            }
            $Results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        }

        $Results |
        Group-Object Setting, Status |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Setting = $_.Group[0].Setting
                Status  = $_.Group[0].Status
                Count   = $_.Count
            }
        } |
        Format-Table -AutoSize

        $BlockingResults = @($Results | Where-Object Status -in @('Drift', 'Failed'))
        if ($BlockingResults.Count -gt 0) {
            Write-Error -ErrorAction Continue "$($BlockingResults.Count) baseline checks require attention."
            exit 1
        }

        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Repository baseline failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
