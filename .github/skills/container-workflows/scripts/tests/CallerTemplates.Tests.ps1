#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $templates = Join-Path $PSScriptRoot '../../templates'
}

Describe 'Caller templates' -Tag 'Unit' {
    It 'imports a credential-free deployment example with safe commit defaults' {
        $path = Join-Path $TestDrive 'deploy.local.psd1'
        Copy-Item -LiteralPath (Join-Path $templates 'deploy.local.psd1.example') -Destination $path
        $data = Import-PowerShellDataFile -LiteralPath $path
        $data.NoCommit | Should -BeTrue
        $data.Chart | Should -BeFalse
        $data.ContainsKey('MigrationConnectionString') | Should -BeFalse
        foreach ($key in @('ManifestRepo', 'ManifestPath', 'PodAnnotationName')) {
            $data[$key] | Should -Not -BeNullOrEmpty
        }
        $implementation = Join-Path $PSScriptRoot '../Invoke-Deploy.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($implementation, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        foreach ($key in $data.Keys) {
            $ast.ParamBlock.Parameters.Name.VariablePath.UserPath | Should -Contain $key
        }
    }

    It 'forwards <Operation> arguments and exit status using the <Resolution> implementation' -TestCases @(
        @{ Operation = 'Build'; Resolution = 'profile' }
        @{ Operation = 'Deploy'; Resolution = 'profile' }
        @{ Operation = 'Build'; Resolution = 'sibling' }
        @{ Operation = 'Deploy'; Resolution = 'sibling' }
    ) {
        param($Operation, $Resolution)
        $root = Join-Path $TestDrive "$Operation-$Resolution"
        $caller = Join-Path $root 'caller with spaces'
        $homePath = Join-Path $root 'home'
        $profileScripts = Join-Path $homePath '.copilot/skills/container-workflows/scripts'
        $siblingScripts = Join-Path $root '.github/.github/skills/container-workflows/scripts'
        New-Item -ItemType Directory -Path $caller, $profileScripts, $siblingScripts -Force | Out-Null
        $entrypoint = Join-Path $caller "$($Operation.ToLowerInvariant()).ps1"
        $content = (Get-Content -LiteralPath (Join-Path $templates 'entrypoint.ps1.tmpl') -Raw).
            Replace('{{IMPLEMENTATION}}', $Operation)
        $content | Should -Not -Match '\{\{.+?\}\}'
        Set-Content -LiteralPath $entrypoint -Value $content -NoNewline
        $stub = @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$RepositoryRoot, [string]$Tag)
[pscustomobject]@{ Root = $RepositoryRoot; Tag = $Tag; Preview = $WhatIfPreference } | ConvertTo-Json -Compress
exit 23
'@
        $selected = if ($Resolution -eq 'profile') { $profileScripts } else { $siblingScripts }
        Set-Content -LiteralPath (Join-Path $selected "Invoke-$Operation.ps1") -Value $stub
        if ($Resolution -eq 'profile') {
            Set-Content -LiteralPath (Join-Path $siblingScripts "Invoke-$Operation.ps1") -Value 'throw "Wrong resolution order"'
        }
        $escapedHome = $homePath.Replace("'", "''")
        $escapedEntrypoint = $entrypoint.Replace("'", "''")
        $result = & pwsh -NoProfile -Command "Set-Variable HOME '$escapedHome' -Force; & '$escapedEntrypoint' -Tag 'tag with spaces' -WhatIf; exit `$LASTEXITCODE"
        $LASTEXITCODE | Should -Be 23
        $actual = $result | ConvertFrom-Json
        $actual.Root | Should -Be $caller
        $actual.Tag | Should -Be 'tag with spaces'
        $actual.Preview | Should -BeTrue
    }

    It 'fails explicitly when neither shared implementation exists' {
        $root = Join-Path $TestDrive 'missing'
        $caller = Join-Path $root 'caller'
        $homePath = Join-Path $root 'home'
        New-Item -ItemType Directory -Path $caller, $homePath -Force | Out-Null
        $entrypoint = Join-Path $caller 'build.ps1'
        $content = (Get-Content -LiteralPath (Join-Path $templates 'entrypoint.ps1.tmpl') -Raw).
            Replace('{{IMPLEMENTATION}}', 'Build')
        Set-Content -LiteralPath $entrypoint -Value $content -NoNewline
        $result = & pwsh -NoProfile -Command "Set-Variable HOME '$($homePath.Replace("'", "''"))' -Force; & '$($entrypoint.Replace("'", "''"))'" 2>&1
        $LASTEXITCODE | Should -Not -Be 0
        "$result" | Should -Match 'Link the central skills folder'
    }
}
