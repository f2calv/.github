#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Set-DotNetLogTemplateCasing.ps1')
}

Describe 'Set-LogTemplateCasing' -Tag 'Unit' {
    BeforeEach {
        $script:SourcePath = Join-Path $TestDrive 'Logging.cs'
        [IO.File]::WriteAllText($script:SourcePath, @'
public sealed class Logging
{
    public void Run(ILogger logger)
    {
        logger.LogInformation("{@request} {bytes:0.0} {RightName}", 1, 2, 3);
    }
}
'@)
        Mock Get-TrackedLogSource {
            @([pscustomobject]@{ RelativePath = 'Logging.cs'; FullPath = $script:SourcePath })
        }
    }

    It 'Reports changes without writing in Check mode' {
        $before = [IO.File]::ReadAllText($script:SourcePath)
        $changes = @(Set-LogTemplateCasing -RepositoryPath $TestDrive -Check)

        $changes | Should -HaveCount 1
        [IO.File]::ReadAllText($script:SourcePath) | Should -BeExactly $before
    }

    It 'Honors WhatIf without writing' {
        $before = [IO.File]::ReadAllText($script:SourcePath)
        $null = Set-LogTemplateCasing -RepositoryPath $TestDrive -WhatIf

        [IO.File]::ReadAllText($script:SourcePath) | Should -BeExactly $before
    }

    It 'Fixes casing and is idempotent' {
        $changes = @(Set-LogTemplateCasing -RepositoryPath $TestDrive -Confirm:$false)
        $updated = [IO.File]::ReadAllText($script:SourcePath)

        $changes | Should -HaveCount 1
        $changes[0].Replacements | Should -Be 2
        $updated | Should -Match '\{@Request\}'
        $updated | Should -Match '\{Bytes:0\.0\}'
        $updated | Should -Match '\{RightName\}'
        @(Set-LogTemplateCasing -RepositoryPath $TestDrive -Confirm:$false) | Should -BeNullOrEmpty
    }
}
