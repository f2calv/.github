#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\New-GitHubRepository.ps1'
    . $script:ScriptPath

    function New-TestCommandResult {
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
}

Describe 'Invoke-NewGitHubRepository' -Tag 'Unit' {
    BeforeEach {
        Mock Test-NativeCommandAvailable { $true }
        Mock Write-Host {}
    }

    It 'Resolves the owner and plans every phase without invoking a mutation under WhatIf' {
        Mock Invoke-NativeCommand {
            if ($FileName -eq 'gh' -and $Arguments[0] -eq 'api') {
                return New-TestCommandResult -Output 'synthetic-owner'
            }
            if ($FileName -eq 'gh' -and $Arguments[0] -eq 'repo' -and $Arguments[1] -eq 'view') {
                return New-TestCommandResult -ExitCode 1 `
                    -Error "GraphQL: Could not resolve to a Repository with the name 'synthetic-repository'."
            }

            throw "Unexpected native command: $FileName $Arguments"
        }

        $Result = Invoke-NewGitHubRepository `
            -Name 'synthetic-repository' `
            -CloneRoot $TestDrive `
            -AddToWorkspace `
            -WhatIf

        $Result.FullName | Should -Be 'synthetic-owner/synthetic-repository'
        $Result.Status | Should -Be 'Planned'
        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter {
            $FileName -eq 'gh' -and $Arguments[0] -eq 'api' -and $Arguments[1] -eq 'user'
        }
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly -ParameterFilter {
            ($FileName -eq 'gh' -and $Arguments[1] -in @('create', 'clone')) -or
            $FileName -in @('pwsh', 'code')
        }
    }

    It 'Rejects NoClone with AddToWorkspace before invoking a native command' {
        Mock Invoke-NativeCommand { throw 'No native command should run.' }

        {
            Invoke-NewGitHubRepository `
                -Name 'synthetic-repository' `
                -Owner 'synthetic-owner' `
                -CloneRoot $TestDrive `
                -NoClone `
                -AddToWorkspace
        } | Should -Throw -ExpectedMessage '*AddToWorkspace requires a local clone*'

        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
    }

    It 'Does not treat authentication failures as a missing repository' {
        Mock Invoke-NativeCommand {
            return New-TestCommandResult -ExitCode 1 -Error 'HTTP 401: Bad credentials'
        }

        {
            Invoke-NewGitHubRepository `
                -Name 'synthetic-repository' `
                -Owner 'synthetic-owner' `
                -CloneRoot $TestDrive `
                -NoClone `
                -WhatIf
        } | Should -Throw -ExpectedMessage '*repository lookup failed*Bad credentials*'

        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly -ParameterFilter {
            $FileName -eq 'gh' -and $Arguments[1] -eq 'create'
        }
    }

    It 'Rejects a resumed clone whose origin points at another repository' {
        $ClonePath = Join-Path $TestDrive 'synthetic-repository'
        New-Item -ItemType Directory -Path $ClonePath | Out-Null
        Mock Invoke-NativeCommand {
            if ($FileName -eq 'gh' -and $Arguments[1] -eq 'view') {
                return New-TestCommandResult -Output '{"nameWithOwner":"synthetic-owner/synthetic-repository"}'
            }
            if ($FileName -eq 'git') {
                return New-TestCommandResult -Output 'https://github.com/another-owner/another-repository.git'
            }

            throw "Unexpected native command: $FileName $Arguments"
        }

        {
            Invoke-NewGitHubRepository `
                -Name 'synthetic-repository' `
                -Owner 'synthetic-owner' `
                -CloneRoot $TestDrive `
                -Resume
        } | Should -Throw -ExpectedMessage '*does not use synthetic-owner/synthetic-repository as its GitHub origin*'
    }

    It 'Stops after repository creation when baseline reconciliation fails' {
        Mock Invoke-NativeCommand {
            if ($FileName -eq 'gh' -and $Arguments[1] -eq 'view') {
                return New-TestCommandResult -ExitCode 1 `
                    -Error "GraphQL: Could not resolve to a Repository with the name 'synthetic-repository'."
            }
            if ($FileName -eq 'gh' -and $Arguments[1] -eq 'create') {
                return New-TestCommandResult
            }
            if ($FileName -eq 'pwsh') {
                return New-TestCommandResult -ExitCode 1 -Error 'synthetic baseline failure'
            }

            throw "Unexpected native command: $FileName $Arguments"
        }

        {
            Invoke-NewGitHubRepository `
                -Name 'synthetic-repository' `
                -Owner 'synthetic-owner' `
                -CloneRoot $TestDrive `
                -NoClone
        } | Should -Throw -ExpectedMessage '*baseline reconciliation failed*synthetic baseline failure*'

        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter {
            $FileName -eq 'pwsh'
        }
        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly -ParameterFilter {
            $FileName -eq 'gh' -and $Arguments[1] -eq 'clone'
        }
    }
}