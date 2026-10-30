#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\Set-EditorConfig.ps1'
    $script:FragmentRoot = Join-Path $PSScriptRoot '../../fragments'
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
    It 'resolves the <Profile> fragments from an isolated skill copy' -ForEach @(
        @{ Profile = 'Base' }
        @{ Profile = 'DotNet' }
        @{ Profile = 'Go' }
        @{ Profile = 'Python' }
        @{ Profile = 'Rust' }
        @{ Profile = 'Terraform' }
    ) {
        $RepositoryPath = New-TestRepository -Name "entry-point-$Profile"
        $SkillPath = Join-Path $TestDrive "standalone-skill-$Profile"
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../..') -Destination $SkillPath -Recurse
        $StandaloneScript = Join-Path $SkillPath 'scripts/Set-EditorConfig.ps1'
        & pwsh -NoLogo -NoProfile -File $StandaloneScript -RepositoryPath $RepositoryPath -Profile $Profile
        $LASTEXITCODE | Should -Be 0
        & pwsh -NoLogo -NoProfile -File $StandaloneScript -RepositoryPath $RepositoryPath -Profile $Profile -Check
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $RepositoryPath '.editorconfig') | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $RepositoryPath '.editorconfig')) |
            Should -BeExactly (Get-GeneratedEditorConfig -Profile $Profile -FragmentRoot $script:FragmentRoot)
    }

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

    It 'applies the documented migration override after the shared profile and checks the same inputs' {
        $RepositoryPath = New-TestRepository -Name 'migration-example'
        $OverridePath = Join-Path $RepositoryPath '.config/editorconfig/overrides.editorconfig'
        New-Item -ItemType Directory -Path (Split-Path $OverridePath -Parent) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../templates/ef-migrations.editorconfig') `
            -Destination $OverridePath
        $Parameters = @{
            RepositoryPath = $RepositoryPath
            Profile = 'DotNet'
            OverridePath = @($OverridePath)
            FragmentRoot = $script:FragmentRoot
        }
        $TargetPath = Join-Path $RepositoryPath '.editorconfig'
        Set-EditorConfigFile @Parameters -WhatIf | Should -Be 'Skipped'
        $TargetPath | Should -Not -Exist
        Set-EditorConfigFile @Parameters | Should -Be 'Updated'
        $Content = [IO.File]::ReadAllText($TargetPath)
        $Section = '[src/Example.Persistence/Migrations/*.cs]'
        $Content.IndexOf($Section) | Should -BeGreaterThan $Content.IndexOf('dotnet_diagnostic.CA1861.severity = warning')
        $Content | Should -Match '\[src/Example\.Persistence/Migrations/\*\.cs\]\ndotnet_diagnostic\.CA1861\.severity = none\n$'
        Set-EditorConfigFile @Parameters -Check | Should -Be 'Unchanged'
        Set-EditorConfigFile @Parameters | Should -Be 'Unchanged'
        {
            Set-EditorConfigFile -RepositoryPath $RepositoryPath -Profile DotNet -FragmentRoot $script:FragmentRoot -Check
        } | Should -Throw '*EditorConfig drift detected*'
        [IO.File]::ReadAllText($TargetPath) | Should -BeExactly $Content
    }
}
