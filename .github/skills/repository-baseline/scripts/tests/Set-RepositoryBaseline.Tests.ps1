#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\Set-RepositoryBaseline.ps1'
    $script:PolicyPath = Join-Path $PSScriptRoot '..\repository-baseline.json'
    . $script:ScriptPath
    $script:Policy = Get-Content -Raw -LiteralPath $script:PolicyPath | ConvertFrom-Json -Depth 100

    function ConvertTo-TestGhResponse {
        param(
            [Parameter(Mandatory = $false)]
            [int]$ExitCode = 0,

            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Output = '',

            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Error = ''
        )

        [pscustomobject]@{
            ExitCode = $ExitCode
            Output   = $Output
            Error    = $Error
        }
    }

    function ConvertTo-TestRuleset {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RepositoryName,

            [Parameter(Mandatory = $true)]
            [string]$Name,

            [Parameter(Mandatory = $false)]
            [int]$Id = 10,

            [Parameter(Mandatory = $false)]
            [switch]$TerraformRules
        )

        $PolicyRepository = if ($TerraformRules) {
            'f2calv/tf_module_azurerm_example'
        }
        else {
            'f2calv/example'
        }
        $Ruleset = Get-DesiredRuleset `
            -Policy $script:Policy `
            -RepositoryName $PolicyRepository
        $Ruleset.name = $Name
        $Ruleset | Add-Member -NotePropertyName id -NotePropertyValue $Id
        $Ruleset | Add-Member -NotePropertyName source_type -NotePropertyValue 'Repository'
        $Ruleset | Add-Member -NotePropertyName source -NotePropertyValue $RepositoryName
        return $Ruleset
    }
}

Describe 'Get-DesiredRuleset' -Tag 'Unit' {
    It 'Builds the shared ruleset without status checks for a private repository' {
        $Ruleset = Get-DesiredRuleset -Policy $script:Policy -RepositoryName 'f2calv/example'

        @($Ruleset.rules.type) | Should -Be @('deletion', 'non_fast_forward', 'pull_request')
    }

    It 'Requires SonarCloud analysis for a public repository without another override' {
        $Ruleset = Get-DesiredRuleset `
            -Policy $script:Policy `
            -RepositoryName 'f2calv/example' `
            -Visibility public
        $StatusChecks = @($Ruleset.rules | Where-Object type -eq 'required_status_checks')

        $StatusChecks.Count | Should -Be 1
        @($StatusChecks.parameters.required_status_checks.context) | Should -Be @(
            'SonarCloud Code Analysis'
        )
    }

    It 'Preserves non-Sonar checks for excluded public repository <Repository>' -TestCases @(
        @{
            Repository = 'f2calv/.github'
            Expected   = @('lint / lint', 'versioning / gha-release-versioning', 'test')
        }
        @{
            Repository = 'f2calv/doorbird-rs'
            Expected   = @()
        }
        @{
            Repository = 'f2calv/gha-check-release-exists'
            Expected   = @('lint / lint', 'versioning / gha-release-versioning', 'validate')
        }
        @{
            Repository = 'f2calv/gha-workflows'
            Expected   = @('lint / lint', 'versioning / gha-release-versioning', 'validate')
        }
        @{
            Repository = 'f2calv/helm-charts'
            Expected   = @('lint / lint', 'release (workload) / versioning / gha-release-versioning', 'release (workload) / chart')
        }
        @{
            Repository = 'f2calv/playground-gitversion'
            Expected   = @()
        }
        @{
            Repository = 'f2calv/signalizr'
            Expected   = @()
        }
        @{
            Repository = 'f2calv/tf_module_azurerm_application_insights'
            Expected   = @('lint / lint', 'versioning / gha-release-versioning', 'validate / terraform validate')
        }
    ) {
        param($Repository, $Expected)

        $Ruleset = Get-DesiredRuleset `
            -Policy $script:Policy `
            -RepositoryName $Repository `
            -Visibility public
        $StatusChecks = @($Ruleset.rules | Where-Object type -eq 'required_status_checks')

        $StatusChecks.Count | Should -Be $(if ($Expected.Count -eq 0) { 0 } else { 1 })
        $Actual = if ($StatusChecks.Count -eq 0) {
            @()
        }
        else {
            @($StatusChecks[0].parameters.required_status_checks.context)
        }
        $Actual | Should -Be $Expected
    }

    It 'Adds the approved status checks for a Terraform module repository' {
        $Ruleset = Get-DesiredRuleset `
            -Policy $script:Policy `
            -RepositoryName 'f2calv/tf_module_azurerm_example' `
            -Visibility public
        $StatusChecks = $Ruleset.rules | Where-Object type -eq 'required_status_checks'

        @($StatusChecks.parameters.required_status_checks.context) | Should -Be @(
            'lint / lint',
            'versioning / gha-release-versioning',
            'validate / terraform validate',
            'SonarCloud Code Analysis'
        )
        $StatusChecks.parameters.strict_required_status_checks_policy | Should -BeTrue
        $StatusChecks.parameters.do_not_enforce_on_create | Should -BeFalse
    }

    It 'Adds the approved status checks for <Repository>' -TestCases @(
        @{
            Repository = 'f2calv/SmartHaus'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'build / app-build-dotnet'
        }
        @{
            Repository = 'f2calv/redis-dotnet'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'build / app-build-dotnet'
        }
        @{
            Repository = 'f2calv/CasCap.Api.Example'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'build'
        }
        @{
            Repository = 'f2calv/yamlizr'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'build'
        }
        @{
            Repository = 'f2calv/dotnet-nuget-test'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'build'
        }
        @{
            Repository = 'f2calv/gha-dotnet-nuget'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'validate'
        }
        @{
            Repository = 'f2calv/gha-gitops-manifest-update'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'validate'
        }
        @{
            Repository = 'f2calv/gha-sonarqube-dotnet'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'validate'
        }
        @{
            Repository = 'f2calv/gha-release-versioning'
            Versioning = 'versioning'
            Validation = 'validate'
        }
        @{
            Repository = 'f2calv/multi-arch-container-dotnet'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'app / app-build-dotnet'
        }
        @{
            Repository = 'f2calv/multi-arch-container-go'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'app / app-build-go'
        }
        @{
            Repository = 'f2calv/multi-arch-container-python'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'app / app-build-python'
        }
        @{
            Repository = 'f2calv/multi-arch-container-rust'
            Versioning = 'versioning / gha-release-versioning'
            Validation = 'app / app-build-rust'
        }
    ) {
        param($Repository, $Versioning, $Validation)

        $Ruleset = Get-DesiredRuleset `
            -Policy $script:Policy `
            -RepositoryName $Repository `
            -Visibility public
        $StatusChecks = @($Ruleset.rules | Where-Object type -eq 'required_status_checks')

        $StatusChecks.Count | Should -Be 1
        @($StatusChecks.parameters.required_status_checks.context) | Should -Be @(
            'lint / lint',
            $Versioning,
            $Validation,
            'SonarCloud Code Analysis'
        )
        $StatusChecks.parameters.strict_required_status_checks_policy | Should -BeTrue
        $StatusChecks.parameters.do_not_enforce_on_create | Should -BeFalse
    }
}

Describe 'Test-RulesetMatchesPolicy' -Tag 'Unit' {
    It 'Accepts the canonical ruleset with server-generated response properties' {
        $Expected = Get-DesiredRuleset -Policy $script:Policy -RepositoryName 'f2calv/example'
        $Actual = Copy-JsonObject -InputObject $Expected
        $Actual | Add-Member -NotePropertyName source_type -NotePropertyValue 'Repository'
        $Actual | Add-Member -NotePropertyName source -NotePropertyValue 'f2calv/example'
        $Actual.rules[2].parameters | Add-Member -NotePropertyName required_reviewers -NotePropertyValue @()

        Test-RulesetMatchesPolicy `
            -Actual $Actual `
            -Expected $Expected `
            -RepositoryName 'f2calv/example' | Should -BeTrue
    }

    It 'Rejects a differently named ruleset' {
        $Expected = Get-DesiredRuleset -Policy $script:Policy -RepositoryName 'f2calv/example'
        $Actual = Copy-JsonObject -InputObject $Expected
        $Actual.name = 'default'
        $Actual | Add-Member -NotePropertyName source_type -NotePropertyValue 'Repository'
        $Actual | Add-Member -NotePropertyName source -NotePropertyValue 'f2calv/example'

        Test-RulesetMatchesPolicy `
            -Actual $Actual `
            -Expected $Expected `
            -RepositoryName 'f2calv/example' | Should -BeFalse
    }

    It 'Rejects stale status checks on a normal repository' {
        $Expected = Get-DesiredRuleset -Policy $script:Policy -RepositoryName 'f2calv/example'
        $Actual = Get-DesiredRuleset `
            -Policy $script:Policy `
            -RepositoryName 'f2calv/tf_module_azurerm_example'
        $Actual.name = $Expected.name
        $Actual | Add-Member -NotePropertyName source_type -NotePropertyValue 'Repository'
        $Actual | Add-Member -NotePropertyName source -NotePropertyValue 'f2calv/example'

        Test-RulesetMatchesPolicy `
            -Actual $Actual `
            -Expected $Expected `
            -RepositoryName 'f2calv/example' | Should -BeFalse
    }

    It 'Rejects a Terraform module ruleset without the approved status checks' {
        $Expected = Get-DesiredRuleset `
            -Policy $script:Policy `
            -RepositoryName 'f2calv/tf_module_azurerm_example'
        $Actual = Get-DesiredRuleset -Policy $script:Policy -RepositoryName 'f2calv/example'
        $Actual | Add-Member -NotePropertyName source_type -NotePropertyValue 'Repository'
        $Actual | Add-Member -NotePropertyName source -NotePropertyValue 'f2calv/tf_module_azurerm_example'

        Test-RulesetMatchesPolicy `
            -Actual $Actual `
            -Expected $Expected `
            -RepositoryName 'f2calv/tf_module_azurerm_example' | Should -BeFalse
    }
}

Describe 'Test-AutomatedSecurityFixesEnabled' -Tag 'Unit' {
    It 'Accepts the current GitHub enabled response' {
        $Response = ConvertTo-TestGhResponse -Output '{"enabled":true,"paused":false}'

        Test-AutomatedSecurityFixesEnabled -Response $Response | Should -BeTrue
    }

    It 'Rejects the GitHub disabled response' {
        $Response = ConvertTo-TestGhResponse -ExitCode 1 -Error 'HTTP 404'

        Test-AutomatedSecurityFixesEnabled -Response $Response | Should -BeFalse
    }
}

Describe 'Resolve-DefaultBranchRuleset' -Tag 'Unit' {
    BeforeEach {
        $script:RepositoryName = 'f2calv/example'
        $script:RepositoryPath = 'repos/f2calv/example'
        $script:UpdatedRuleset = $null
        $script:MutationBody = $null
    }

    It 'Reports a historical ruleset as drift during audit' {
        $Historical = ConvertTo-TestRuleset `
            -RepositoryName $script:RepositoryName `
            -Name 'default'

        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output (@(@{ id = 10 }) | ConvertTo-Json)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/10") {
                return ConvertTo-TestGhResponse -Output ($Historical | ConvertTo-Json -Depth 100)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -ExitCode 1 -Error 'HTTP 404'
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation { throw 'Audit must not mutate GitHub.' }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy

        $Result.Status | Should -Be 'Drift'
        $Result.Detail | Should -Match 'historical baseline ruleset'
        Should -Invoke Invoke-GhMutation -Times 0 -Exactly
    }

    It 'Renames a historical ruleset and removes stale checks outside Terraform modules' {
        $Historical = ConvertTo-TestRuleset `
            -RepositoryName $script:RepositoryName `
            -Name 'default' `
            -TerraformRules

        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output (@(@{ id = 10 }) | ConvertTo-Json)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/10") {
                $Ruleset = if ($null -eq $script:UpdatedRuleset) { $Historical } else { $script:UpdatedRuleset }
                return ConvertTo-TestGhResponse -Output ($Ruleset | ConvertTo-Json -Depth 100)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -ExitCode 1 -Error 'HTTP 404'
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation {
            $script:MutationBody = $Body
            $script:UpdatedRuleset = Copy-JsonObject -InputObject $Body
            $script:UpdatedRuleset | Add-Member -NotePropertyName id -NotePropertyValue 10
            $script:UpdatedRuleset | Add-Member -NotePropertyName source_type -NotePropertyValue 'Repository'
            $script:UpdatedRuleset | Add-Member -NotePropertyName source -NotePropertyValue $script:RepositoryName
            return ConvertTo-TestGhResponse -Output ($script:UpdatedRuleset | ConvertTo-Json -Depth 100)
        }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy `
            -Apply

        $Result.Status | Should -Be 'Changed'
        $script:MutationBody.name | Should -Be 'f2calv repository baseline'
        @($script:MutationBody.rules.type) | Should -Not -Contain 'required_status_checks'
        Should -Invoke Invoke-GhMutation -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Path -eq 'repos/f2calv/example/rulesets/10'
        }
    }

    It 'Creates a Terraform ruleset with approved checks before deleting classic protection' {
        $script:RepositoryName = 'f2calv/tf_module_azurerm_example'
        $script:RepositoryPath = 'repos/f2calv/tf_module_azurerm_example'
        $script:ClassicProtectionDeleted = $false

        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output '[]'
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -Output '{}'
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/20") {
                return ConvertTo-TestGhResponse -Output ($script:UpdatedRuleset | ConvertTo-Json -Depth 100)
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation {
            if ($Method -eq 'POST') {
                $script:MutationBody = $Body
                $script:UpdatedRuleset = Copy-JsonObject -InputObject $Body
                $script:UpdatedRuleset | Add-Member -NotePropertyName id -NotePropertyValue 20
                $script:UpdatedRuleset | Add-Member -NotePropertyName source_type -NotePropertyValue 'Repository'
                $script:UpdatedRuleset | Add-Member -NotePropertyName source -NotePropertyValue $script:RepositoryName
                return ConvertTo-TestGhResponse -Output ($script:UpdatedRuleset | ConvertTo-Json -Depth 100)
            }

            $script:ClassicProtectionDeleted = $true
            return ConvertTo-TestGhResponse
        }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy `
            -Apply

        $Result.Status | Should -Be 'Changed'
        @($script:MutationBody.rules.type) | Should -Contain 'required_status_checks'
        $script:ClassicProtectionDeleted | Should -BeTrue
        Should -Invoke Invoke-GhMutation -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Path -eq 'repos/f2calv/tf_module_azurerm_example/branches/main/protection'
        }
    }

    It 'Retains classic protection when canonical verification fails' {
        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output '[]'
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -Output '{}'
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/20") {
                $Invalid = ConvertTo-TestRuleset `
                    -RepositoryName $script:RepositoryName `
                    -Name 'wrong-name' `
                    -Id 20
                return ConvertTo-TestGhResponse -Output ($Invalid | ConvertTo-Json -Depth 100)
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation {
            return ConvertTo-TestGhResponse -Output '{"id":20}'
        }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy `
            -Apply

        $Result.Status | Should -Be 'Failed'
        $Result.Detail | Should -Match 'superseded protection was retained'
        Should -Invoke Invoke-GhMutation -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'Retains classic protection when the verification API call fails' {
        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output '[]'
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -Output '{}'
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/20") {
                return ConvertTo-TestGhResponse -ExitCode 1 -Error 'HTTP 503'
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation {
            return ConvertTo-TestGhResponse -Output '{"id":20}'
        }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy `
            -Apply

        $Result.Status | Should -Be 'Failed'
        $Result.Detail | Should -Match 'superseded protection was retained'
        Should -Invoke Invoke-GhMutation -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'Does not mutate an already canonical repository' {
        $Canonical = ConvertTo-TestRuleset `
            -RepositoryName $script:RepositoryName `
            -Name 'f2calv repository baseline'

        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output (@(@{ id = 10 }) | ConvertTo-Json)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/10") {
                return ConvertTo-TestGhResponse -Output ($Canonical | ConvertTo-Json -Depth 100)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -ExitCode 1 -Error 'HTTP 404'
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation { throw 'Compliant repositories must not be mutated.' }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy `
            -Apply

        $Result.Status | Should -Be 'Compliant'
        Should -Invoke Invoke-GhMutation -Times 0 -Exactly
    }

    It 'Removes classic protection without rewriting a compliant canonical ruleset' {
        $Canonical = ConvertTo-TestRuleset `
            -RepositoryName $script:RepositoryName `
            -Name 'f2calv repository baseline'

        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output (@(@{ id = 10 }) | ConvertTo-Json)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/10") {
                return ConvertTo-TestGhResponse -Output ($Canonical | ConvertTo-Json -Depth 100)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -Output '{}'
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation { return ConvertTo-TestGhResponse }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy `
            -Apply

        $Result.Status | Should -Be 'Changed'
        Should -Invoke Invoke-GhMutation -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Path -eq 'repos/f2calv/example/branches/main/protection'
        }
        Should -Invoke Invoke-GhMutation -Times 0 -Exactly -ParameterFilter {
            $Method -in @('POST', 'PUT')
        }
    }

    It 'Does not mutate drift when WhatIf is enabled' {
        $Historical = ConvertTo-TestRuleset `
            -RepositoryName $script:RepositoryName `
            -Name 'default'

        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output (@(@{ id = 10 }) | ConvertTo-Json)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/10") {
                return ConvertTo-TestGhResponse -Output ($Historical | ConvertTo-Json -Depth 100)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -ExitCode 1 -Error 'HTTP 404'
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation { throw 'WhatIf must not mutate GitHub.' }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy `
            -Apply `
            -WhatIf

        $Result.Status | Should -Be 'WhatIf'
        Should -Invoke Invoke-GhMutation -Times 0 -Exactly
    }

    It 'Creates the canonical ruleset without deleting an unrelated custom ruleset' {
        $Custom = ConvertTo-TestRuleset `
            -RepositoryName $script:RepositoryName `
            -Name 'production deployment policy'
        $Custom.rules += [pscustomobject]@{
            type       = 'required_deployments'
            parameters = [pscustomobject]@{
                required_deployment_environments = @('production')
            }
        }

        Mock Invoke-GhCommand {
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets?includes_parents=false&per_page=100") {
                return ConvertTo-TestGhResponse -Output (@(@{ id = 10 }) | ConvertTo-Json)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/10") {
                return ConvertTo-TestGhResponse -Output ($Custom | ConvertTo-Json -Depth 100)
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/branches/main/protection") {
                return ConvertTo-TestGhResponse -ExitCode 1 -Error 'HTTP 404'
            }
            if ($Arguments[1] -eq "$script:RepositoryPath/rulesets/20") {
                return ConvertTo-TestGhResponse -Output ($script:UpdatedRuleset | ConvertTo-Json -Depth 100)
            }

            throw "Unexpected GitHub API path: $($Arguments[1])"
        }
        Mock Invoke-GhMutation {
            if ($Method -ne 'POST') {
                throw "Unexpected mutation: $Method $Path"
            }

            $script:UpdatedRuleset = Copy-JsonObject -InputObject $Body
            $script:UpdatedRuleset | Add-Member -NotePropertyName id -NotePropertyValue 20
            $script:UpdatedRuleset | Add-Member -NotePropertyName source_type -NotePropertyValue 'Repository'
            $script:UpdatedRuleset | Add-Member -NotePropertyName source -NotePropertyValue $script:RepositoryName
            return ConvertTo-TestGhResponse -Output ($script:UpdatedRuleset | ConvertTo-Json -Depth 100)
        }

        $Result = Resolve-DefaultBranchRuleset `
            -RepositoryName $script:RepositoryName `
            -RepositoryPath $script:RepositoryPath `
            -DefaultBranch main `
            -Policy $script:Policy `
            -Apply

        $Result.Status | Should -Be 'Changed'
        Should -Invoke Invoke-GhMutation -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq 'repos/f2calv/example/rulesets'
        }
        Should -Invoke Invoke-GhMutation -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Path -eq 'repos/f2calv/example/rulesets/10'
        }
    }
}
