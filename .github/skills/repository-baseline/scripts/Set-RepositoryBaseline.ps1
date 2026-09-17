#!/usr/bin/env pwsh
#Requires -Version 7.4

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
    ./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 -Repository f2calv/example -Mode Apply
.EXAMPLE
    ./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Audit
.EXAMPLE
    ./skills/repository-baseline/scripts/Set-RepositoryBaseline.ps1 -AllOwned -Mode Apply -WhatIf
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
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version 3.0

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

function Test-AutomatedSecurityFixesEnabled {
    <#
    .SYNOPSIS
        Tests whether GitHub reports automated security fixes as enabled.
    .PARAMETER Response
        Response from the automated-security-fixes endpoint.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Response
    )

    if ($Response.ExitCode -ne 0) {
        return $false
    }

    $Payload = ConvertFrom-GhResponse -Response $Response
    return $null -ne $Payload -and
    $Payload.PSObject.Properties.Name -contains 'enabled' -and
    $Payload.enabled
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

function Get-RepositoryTarget {
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
    [OutputType([string])]
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
        $Pages |
            ForEach-Object { $_ } |
            Where-Object {
                -not $_.fork -and
                -not $_.archived -and
                -not $_.disabled -and
                $_.owner.login -eq $AuthenticatedOwner
            } |
            ForEach-Object { $_.full_name } |
            Sort-Object -Unique
        return
    }

    $RepositoryNames | ForEach-Object {
            if ($_ -match '/') {
                $_
            }
            else {
                "$AuthenticatedOwner/$_"
            }
        } | Sort-Object -Unique
}

function Copy-JsonObject {
    <#
    .SYNOPSIS
        Creates an independent copy of a JSON-compatible object.
    .PARAMETER InputObject
        Object to copy.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    $InputObject | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
}

function Get-DesiredRuleset {
    <#
    .SYNOPSIS
        Builds the complete managed ruleset for a repository.
    .PARAMETER Policy
        Baseline policy document.
    .PARAMETER RepositoryName
        Repository in owner/name format.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Policy,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName
    )

    $DesiredRuleset = Copy-JsonObject -InputObject $Policy.ruleset
    $Rules = [Collections.Generic.List[object]]::new()
    foreach ($Rule in @($DesiredRuleset.rules)) {
        $Rules.Add($Rule)
    }

    if ($Policy.PSObject.Properties.Name -contains 'rulesetOverrides') {
        foreach ($Override in @($Policy.rulesetOverrides)) {
            if ($RepositoryName -notlike $Override.repositoryPattern) {
                continue
            }

            foreach ($Rule in @($Override.rules)) {
                $Rules.Add((Copy-JsonObject -InputObject $Rule))
            }
        }
    }

    $DesiredRuleset.rules = @($Rules)
    return $DesiredRuleset
}

function Test-PolicyValue {
    <#
    .SYNOPSIS
        Tests whether an API value contains the expected policy value.
    .PARAMETER Actual
        Value returned by GitHub.
    .PARAMETER Expected
        Value declared by policy.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Actual,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Expected
    )

    if ($null -eq $Expected) {
        return $null -eq $Actual
    }

    if ($Expected -is [array]) {
        if ($Actual -isnot [array] -or $Actual.Count -ne $Expected.Count) {
            return $false
        }

        for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
            if (-not (Test-PolicyValue -Actual $Actual[$Index] -Expected $Expected[$Index])) {
                return $false
            }
        }

        return $true
    }

    if ($Expected -is [pscustomobject]) {
        if ($Actual -isnot [pscustomobject]) {
            return $false
        }

        foreach ($Property in $Expected.PSObject.Properties) {
            if ($Actual.PSObject.Properties.Name -notcontains $Property.Name -or
                -not (Test-PolicyValue -Actual $Actual.$($Property.Name) -Expected $Property.Value)) {
                return $false
            }
        }

        return $true
    }

    return $Actual -ceq $Expected
}

function Test-RulesetMatchesPolicy {
    <#
    .SYNOPSIS
        Tests whether a repository ruleset matches the managed policy.
    .PARAMETER Actual
        Detailed ruleset returned by GitHub.
    .PARAMETER Expected
        Desired ruleset built from policy.
    .PARAMETER RepositoryName
        Repository in owner/name format.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Actual,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Expected,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName
    )

    if ($Actual.source_type -ne 'Repository' -or $Actual.source -ne $RepositoryName) {
        return $false
    }

    Test-PolicyValue -Actual $Actual -Expected $Expected
}

function Test-RulesetContainsBaseline {
    <#
    .SYNOPSIS
        Tests whether a historical ruleset contains the managed baseline rules.
    .PARAMETER Actual
        Detailed ruleset returned by GitHub.
    .PARAMETER Policy
        Baseline policy document.
    .PARAMETER RepositoryName
        Repository in owner/name format.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Actual,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Policy,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName
    )

    $HistoricalNames = if ($Policy.PSObject.Properties.Name -contains 'historicalRulesetNames') {
        @($Policy.historicalRulesetNames)
    }
    else {
        @()
    }
    $ManagedNames = @($Policy.ruleset.name) + $HistoricalNames
    if ($Actual.name -notin $ManagedNames) {
        return $false
    }

    $AllowedRuleTypes = @($Policy.ruleset.rules.type) + 'required_status_checks'
    if (@($Actual.rules | Where-Object type -notin $AllowedRuleTypes).Count -gt 0) {
        return $false
    }

    $Expected = Copy-JsonObject -InputObject $Policy.ruleset
    $Expected.name = $Actual.name
    $ManagedRuleTypes = @($Expected.rules.type)
    $Candidate = Copy-JsonObject -InputObject $Actual
    $Candidate.rules = @($Candidate.rules | Where-Object type -in $ManagedRuleTypes)

    Test-RulesetMatchesPolicy `
        -Actual $Candidate `
        -Expected $Expected `
        -RepositoryName $RepositoryName
}

function Resolve-DefaultBranchRuleset {
    <#
    .SYNOPSIS
        Audits or reconciles the canonical default-branch ruleset.
    .PARAMETER RepositoryName
        Repository in owner/name format.
    .PARAMETER RepositoryPath
        GitHub REST API repository path.
    .PARAMETER DefaultBranch
        Repository default branch.
    .PARAMETER Policy
        Baseline policy document.
    .PARAMETER Apply
        Reconciles drift when specified.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefaultBranch,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Policy,

        [Parameter(Mandatory = $false)]
        [switch]$Apply
    )

    $RulesetsPath = "$RepositoryPath/rulesets?includes_parents=false&per_page=100"
    $RulesetsResponse = Invoke-GhCommand -Arguments @('api', $RulesetsPath)
    if ($RulesetsResponse.ExitCode -ne 0) {
        return [pscustomobject]@{
            Status = Get-FailureStatus $RulesetsResponse.Error
            Detail = $RulesetsResponse.Error
        }
    }

    $Rulesets = [Collections.Generic.List[object]]::new()
    foreach ($RulesetSummary in @(ConvertFrom-GhResponse -Response $RulesetsResponse)) {
        $RulesetResponse = Invoke-GhCommand -Arguments @(
            'api',
            "$RepositoryPath/rulesets/$($RulesetSummary.id)")
        if ($RulesetResponse.ExitCode -ne 0) {
            return [pscustomobject]@{
                Status = 'Failed'
                Detail = $RulesetResponse.Error
            }
        }

        $Rulesets.Add((ConvertFrom-GhResponse -Response $RulesetResponse))
    }

    $EncodedBranch = [Uri]::EscapeDataString($DefaultBranch)
    $ProtectionPath = "$RepositoryPath/branches/$EncodedBranch/protection"
    $ProtectionResponse = Invoke-GhCommand -Arguments @('api', $ProtectionPath)
    $HasLegacyProtection = $ProtectionResponse.ExitCode -eq 0
    if (-not $HasLegacyProtection -and $ProtectionResponse.Error -notmatch '\bHTTP 404\b') {
        return [pscustomobject]@{
            Status = Get-FailureStatus $ProtectionResponse.Error
            Detail = $ProtectionResponse.Error
        }
    }

    $DesiredRuleset = Get-DesiredRuleset -Policy $Policy -RepositoryName $RepositoryName
    $CanonicalRuleset = $Rulesets |
    Where-Object {
        $_.name -eq $DesiredRuleset.name -and
        $_.source_type -eq 'Repository' -and
        $_.source -eq $RepositoryName
    } |
    Select-Object -First 1
    $CanonicalRulesetId = if ($null -ne $CanonicalRuleset) { $CanonicalRuleset.id } else { $null }
    $HistoricalRulesets = @($Rulesets |
        Where-Object {
            $_.id -ne $CanonicalRulesetId -and
            (Test-RulesetContainsBaseline `
                    -Actual $_ `
                    -Policy $Policy `
                    -RepositoryName $RepositoryName)
        })
    $CanonicalCompliant = $null -ne $CanonicalRuleset -and
    (Test-RulesetMatchesPolicy `
            -Actual $CanonicalRuleset `
            -Expected $DesiredRuleset `
            -RepositoryName $RepositoryName)
    $Compliant = $CanonicalCompliant -and
    -not $HasLegacyProtection -and
    $HistoricalRulesets.Count -eq 0

    if ($Compliant) {
        return [pscustomobject]@{ Status = 'Compliant'; Detail = '' }
    }

    $Drift = [Collections.Generic.List[string]]::new()
    if (-not $CanonicalCompliant) {
        $Drift.Add('Canonical ruleset is missing or differs from policy.')
    }
    if ($HistoricalRulesets.Count -gt 0) {
        $Drift.Add("$($HistoricalRulesets.Count) historical baseline ruleset(s) remain.")
    }
    if ($HasLegacyProtection) {
        $Drift.Add('Classic branch protection remains.')
    }
    $DriftDetail = $Drift -join ' '

    if (-not $Apply) {
        return [pscustomobject]@{ Status = 'Drift'; Detail = $DriftDetail }
    }

    if (-not $PSCmdlet.ShouldProcess(
            $RepositoryName,
            'Reconcile the canonical ruleset and remove superseded branch protection')) {
        return [pscustomobject]@{ Status = 'WhatIf'; Detail = $DriftDetail }
    }

    $RulesetId = $CanonicalRulesetId
    if (-not $CanonicalCompliant) {
        $RulesetToUpdate = if ($null -ne $CanonicalRuleset) {
            $CanonicalRuleset
        }
        else {
            $HistoricalRulesets | Select-Object -First 1
        }

        if ($null -eq $RulesetToUpdate) {
            $MutationResponse = Invoke-GhMutation `
                -Method POST `
                -Path "$RepositoryPath/rulesets" `
                -Body $DesiredRuleset
        }
        else {
            $MutationResponse = Invoke-GhMutation `
                -Method PUT `
                -Path "$RepositoryPath/rulesets/$($RulesetToUpdate.id)" `
                -Body $DesiredRuleset
        }

        if ($MutationResponse.ExitCode -ne 0) {
            return [pscustomobject]@{
                Status = Get-FailureStatus $MutationResponse.Error
                Detail = $MutationResponse.Error
            }
        }

        $MutatedRuleset = ConvertFrom-GhResponse -Response $MutationResponse
        $RulesetId = if ($null -ne $MutatedRuleset -and
            $MutatedRuleset.PSObject.Properties.Name -contains 'id') {
            $MutatedRuleset.id
        }
        elseif ($null -ne $RulesetToUpdate) {
            $RulesetToUpdate.id
        }
        else {
            $null
        }
        if ($null -eq $RulesetId) {
            return [pscustomobject]@{
                Status = 'Failed'
                Detail = 'GitHub did not return the reconciled ruleset identifier.'
            }
        }

        $VerificationResponse = Invoke-GhCommand -Arguments @(
            'api',
            "$RepositoryPath/rulesets/$RulesetId")
        $VerifiedRuleset = ConvertFrom-GhResponse -Response $VerificationResponse
        if ($VerificationResponse.ExitCode -ne 0 -or
            $null -eq $VerifiedRuleset -or
            -not (Test-RulesetMatchesPolicy `
                    -Actual $VerifiedRuleset `
                    -Expected $DesiredRuleset `
                    -RepositoryName $RepositoryName)) {
            return [pscustomobject]@{
                Status = 'Failed'
                Detail = 'Canonical ruleset verification failed; superseded protection was retained.'
            }
        }
    }

    foreach ($HistoricalRuleset in $HistoricalRulesets) {
        if ($HistoricalRuleset.id -eq $RulesetId) {
            continue
        }

        $DeleteResponse = Invoke-GhMutation `
            -Method DELETE `
            -Path "$RepositoryPath/rulesets/$($HistoricalRuleset.id)"
        if ($DeleteResponse.ExitCode -ne 0) {
            return [pscustomobject]@{
                Status = 'Failed'
                Detail = "Canonical ruleset was verified, but a historical ruleset could not be removed: $($DeleteResponse.Error)"
            }
        }
    }

    if ($HasLegacyProtection) {
        $DeleteResponse = Invoke-GhMutation -Method DELETE -Path $ProtectionPath
        if ($DeleteResponse.ExitCode -ne 0) {
            return [pscustomobject]@{
                Status = 'Failed'
                Detail = "Canonical ruleset was verified, but classic branch protection could not be removed: $($DeleteResponse.Error)"
            }
        }
    }

    [pscustomobject]@{ Status = 'Changed'; Detail = $DriftDetail }
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
        $Targets = Get-RepositoryTarget `
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
            $SecurityUpdatesEnabled = Test-AutomatedSecurityFixesEnabled `
                -Response $SecurityUpdatesResponse
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

            $SecurityAnalysis = if ($Detail.PSObject.Properties.Name -contains 'security_and_analysis') {
                $Detail.security_and_analysis
            }
            else {
                $null
            }
            $SecretScanning = if ($null -ne $SecurityAnalysis -and
                $SecurityAnalysis.PSObject.Properties.Name -contains 'secret_scanning') {
                $SecurityAnalysis.secret_scanning
            }
            else {
                $null
            }
            $PushProtection = if ($null -ne $SecurityAnalysis -and
                $SecurityAnalysis.PSObject.Properties.Name -contains 'secret_scanning_push_protection') {
                $SecurityAnalysis.secret_scanning_push_protection
            }
            else {
                $null
            }
            $SecretScanningEnabled = $null -ne $SecretScanning -and $SecretScanning.status -eq 'enabled'
            $PushProtectionEnabled = $null -ne $PushProtection -and $PushProtection.status -eq 'enabled'
            $SecretScanningCompliant =
            $SecretScanningEnabled -eq $Policy.security.secretScanning -and
            $PushProtectionEnabled -eq $Policy.security.secretScanningPushProtection
            if ($SecretScanningCompliant) {
                Add-BaselineResult -Results $Results -RepositoryName $FullName `
                    -Setting 'secret_protection' -Status 'Compliant'
            }
            elseif ($Policy.security.secretScanning -and
                $Detail.visibility -eq 'private' -and
                $null -eq $SecretScanning) {
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

            $RulesetResult = Resolve-DefaultBranchRuleset `
                -RepositoryName $FullName `
                -RepositoryPath $RepositoryPath `
                -DefaultBranch $Detail.default_branch `
                -Policy $Policy `
                -Apply:($Mode -eq 'Apply') `
                -WhatIf:$WhatIfPreference
            Add-BaselineResult -Results $Results -RepositoryName $FullName `
                -Setting 'default_branch_ruleset' `
                -Status $RulesetResult.Status `
                -Detail $RulesetResult.Detail
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
