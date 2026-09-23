#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\Set-EditorConfig.ps1'
    $script:FragmentRoot = Join-Path $PSScriptRoot '..\..\.config\editorconfig'
    . $script:ScriptPath

    function New-TestRepository {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Name
        )

        $RepositoryPath = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $RepositoryPath -Force | Out-Null
        return $RepositoryPath
    }
}

Describe 'Set-EditorConfigFile' -Tag 'Unit' {
    It 'Generates the universal baseline as UTF-8 with LF endings' {
        $RepositoryPath = New-TestRepository -Name 'base'

        $Result = Set-EditorConfigFile `
            -RepositoryPath $RepositoryPath `
            -Profile Base `
            -FragmentRoot $script:FragmentRoot

        $Result | Should -Be 'Updated'
        $TargetPath = Join-Path $RepositoryPath '.editorconfig'
        $Expected = (Get-NormalizedFragment -Path (Join-Path $script:FragmentRoot 'base.editorconfig')) + "`n"
        [IO.File]::ReadAllText($TargetPath) | Should -BeExactly $Expected
        [IO.File]::ReadAllBytes($TargetPath) | Should -Not -Contain 13
        [IO.File]::ReadAllBytes($TargetPath)[-1] | Should -Be 10
    }

    It 'Composes the DotNet profile and repository override in order' {
        $RepositoryPath = New-TestRepository -Name 'dotnet'
        $OverridePath = Join-Path $TestDrive 'override.editorconfig'
        "[*.generated.cs]`ngenerated_code = true" | Set-Content -LiteralPath $OverridePath

        Set-EditorConfigFile `
            -RepositoryPath $RepositoryPath `
            -Profile DotNet `
            -OverridePath $OverridePath `
            -FragmentRoot $script:FragmentRoot | Should -Be 'Updated'

        $Content = [IO.File]::ReadAllText((Join-Path $RepositoryPath '.editorconfig'))
        $Content.IndexOf('[*]') | Should -BeLessThan $Content.IndexOf('[*.cs]')
        $Content.IndexOf('[*.cs]') | Should -BeLessThan $Content.IndexOf('[*.generated.cs]')
        $Content | Should -Match 'dotnet_diagnostic\.IDE0055\.severity = warning'
    }

    It 'Composes the <Profile> language profile' -ForEach @(
        @{ Profile = 'Go'; Section = '[*.go]' }
        @{ Profile = 'Python'; Section = '[*.py]' }
        @{ Profile = 'Rust'; Section = '[*.rs]' }
        @{ Profile = 'Terraform'; Section = '[*.{tf,tfvars,hcl}]' }
    ) {
        $RepositoryPath = New-TestRepository -Name $Profile

        Set-EditorConfigFile `
            -RepositoryPath $RepositoryPath `
            -Profile $Profile `
            -FragmentRoot $script:FragmentRoot | Should -Be 'Updated'

        [IO.File]::ReadAllText((Join-Path $RepositoryPath '.editorconfig')) | Should -Match ([regex]::Escape($Section))
    }

    It 'Leaves matching generated output unchanged' {
        $RepositoryPath = New-TestRepository -Name 'idempotent'
        Set-EditorConfigFile `
            -RepositoryPath $RepositoryPath `
            -Profile Base `
            -FragmentRoot $script:FragmentRoot | Should -Be 'Updated'
        $TargetPath = Join-Path $RepositoryPath '.editorconfig'
        $Before = [IO.File]::ReadAllBytes($TargetPath)

        Set-EditorConfigFile `
            -RepositoryPath $RepositoryPath `
            -Profile Base `
            -FragmentRoot $script:FragmentRoot | Should -Be 'Unchanged'

        [IO.File]::ReadAllBytes($TargetPath) | Should -Be $Before
    }

    It 'Detects drift without modifying the target' {
        $RepositoryPath = New-TestRepository -Name 'drift'
        $TargetPath = Join-Path $RepositoryPath '.editorconfig'
        'drift' | Set-Content -LiteralPath $TargetPath

        {
            Set-EditorConfigFile `
                -RepositoryPath $RepositoryPath `
                -Profile Base `
                -Check `
                -FragmentRoot $script:FragmentRoot
        } | Should -Throw '*EditorConfig drift detected*'
        [IO.File]::ReadAllText($TargetPath).Trim() | Should -BeExactly 'drift'
    }

    It 'Honors WhatIf without creating a target' {
        $RepositoryPath = New-TestRepository -Name 'what-if'

        Set-EditorConfigFile `
            -RepositoryPath $RepositoryPath `
            -Profile Base `
            -FragmentRoot $script:FragmentRoot `
            -WhatIf | Should -Be 'Skipped'

        Join-Path $RepositoryPath '.editorconfig' | Should -Not -Exist
    }
}