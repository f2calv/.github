#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $scriptsRoot = Join-Path $repositoryRoot '.scripts'
    $tokens = $null
    $errors = $null
    $runner = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $scriptsRoot 'Invoke-Tests.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw 'The central test runner has parsing errors.' }
    $discovery = $runner.Find({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
            $node.Extent.Text.StartsWith('if ($TestPath.Count -eq 0)')
        }, $false)
    if ($null -eq $discovery) { throw 'Central test discovery block not found.' }
    $discoveryCode = [scriptblock]::Create($discovery.Extent.Text.Replace('$PSScriptRoot', '$RunnerRoot'))
}

Describe 'Central skill suite discovery' -Tag 'Unit' {
    It 'includes root tests and every bundled skill test directory exactly once' {
        $paths = @(& {
                param($RunnerRoot, $Code)
                $TestPath = @()
                . $Code
                $TestPath
            } $scriptsRoot $discoveryCode)
        $expected = @(
            Join-Path $scriptsRoot 'tests'
            Get-ChildItem -LiteralPath (Join-Path $repositoryRoot '.github/skills') -Directory |
            ForEach-Object {
                $path = Join-Path $_.FullName 'scripts/tests'
                if (Test-Path -LiteralPath $path -PathType Container) { $path }
            }
        )
        @($paths | Sort-Object) | Should -Be @($expected | Sort-Object)
        @($paths | Sort-Object -Unique).Count | Should -Be $paths.Count
        $paths | Should -Contain (Join-Path $repositoryRoot '.github/skills/dotnet-release-train/scripts/tests')
        $paths | Should -Contain (Join-Path $repositoryRoot '.github/skills/pre-commit-management/scripts/tests')
    }

    It 'preserves explicit focused selectors without widening execution' {
        $selected = Join-Path $scriptsRoot 'tests/Skills.Tests.ps1'
        $paths = @(& {
                param($RunnerRoot, $Code, $Selected)
                $TestPath = @($Selected)
                . $Code
                $TestPath
            } $scriptsRoot $discoveryCode $selected)
        $paths | Should -Be @($selected)
    }
}

Describe 'Network evidence boundaries' -Tag 'Unit' {
    It 'keeps synthetic measurements distinct from failed client acceptance and actual network proof' {
        $path = Join-Path $repositoryRoot '.github/skills/unifi-network-management/examples/change-evidence.md'
        $text = Get-Content -LiteralPath $path -Raw
        foreach ($heading in @('Before the Change', 'Worked Observation Sequence', 'Comparable Measurements',
                'Acceptance and Rollback', 'Handoff and Cleanup')) {
            $text | Should -Match "(?m)^## $([regex]::Escape($heading))"
        }
        $text | Should -Match 'invented teaching data'
        $text | Should -Match '\*\*Not accepted\*\*'
        $text | Should -Match '\*\*manual fallback\*\*'
        $text | Should -Match 'three repetitions per stage'
        $text | Should -Match '30 seconds per network run'
        $text | Should -Match 'Gbit/s'
        $text | Should -Match 'MiB/s'
        $text | Should -Match 'validate documentation structure only'
        $text | Should -Not -Match '192\.168\.|10\.\d+\.\d+\.|(?i)([a-f0-9]{2}:){5}[a-f0-9]{2}'
    }
}
