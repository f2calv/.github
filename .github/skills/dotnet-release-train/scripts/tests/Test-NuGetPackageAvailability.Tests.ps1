#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\Test-NuGetPackageAvailability.ps1'
    . $script:ScriptPath -PackageId Example.Package -Version 1.2.3
}

Describe 'Test-NuGetPackageAvailability' -Tag 'Unit' {
    BeforeEach {
        Mock Start-Sleep
    }

    It 'Accepts an exact version case-insensitively' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ versions = @('1.2.2', '1.2.3') }
        }

        $Result = @(Test-NuGetPackageAvailability `
                -PackageId Example.Package `
                -Version 1.2.3 `
                -TimeoutSeconds 10 `
                -InitialDelaySeconds 1 `
                -MaximumDelaySeconds 2)

        $Result.Count | Should -Be 1
        $Result[0].Available | Should -BeTrue
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'Requires every package ID to expose the version' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ versions = @('2.0.0') }
        }

        $Results = @(Test-NuGetPackageAvailability `
                -PackageId Example.Core, Example.Json `
                -Version 2.0.0 `
                -TimeoutSeconds 10 `
                -InitialDelaySeconds 1 `
                -MaximumDelaySeconds 2)

        $Results.Count | Should -Be 2
        @($Results | Where-Object Available).Count | Should -Be 2
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
    }

    It 'Retries a package that is not yet indexed' {
        $script:Attempt = 0
        Mock Invoke-RestMethod {
            $script:Attempt++
            if ($script:Attempt -eq 1) {
                return [pscustomobject]@{ versions = @('3.0.0') }
            }

            [pscustomobject]@{ versions = @('3.0.0', '3.0.1') }
        }

        $Result = @(Test-NuGetPackageAvailability `
                -PackageId Example.Package `
                -Version 3.0.1 `
                -TimeoutSeconds 10 `
                -InitialDelaySeconds 1 `
                -MaximumDelaySeconds 2)

        $Result[0].Available | Should -BeTrue
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly
    }

    It 'Does not expose a package source override' {
        (Get-Command Test-NuGetPackageAvailability).Parameters.Keys | Should -Not -Contain 'BaseUri'
    }
}
