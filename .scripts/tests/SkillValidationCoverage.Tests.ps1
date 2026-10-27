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
    It 'installs hash-locked Python wheels without executing source setup scripts' {
        $json = & yq -o=json '.' (Join-Path $repositoryRoot '.github/workflows/_skills-library-tests.yml')
        $LASTEXITCODE | Should -Be 0
        $workflow = ($json -join "`n") | ConvertFrom-Json -AsHashtable
        $install = @($workflow.jobs.test.steps | Where-Object {
                $_.ContainsKey('run') -and $_.run -match 'python -m pip install'
            })
        $install.Count | Should -Be 1
        $install[0].run | Should -Match '--require-hashes'
        $install[0].run | Should -Match '--only-binary :all:'
        $requirements = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/skills/skill-library/scripts/requirements.txt') -Raw
        $requirements | Should -Match '\APyYAML==[0-9]+\.[0-9]+\.[0-9]+ \\\r?\n'
        $requirements | Should -Not -Match '(?m)^[\t ]+--hash='
        [regex]::Matches($requirements, '--hash=sha256:[0-9a-f]{64}').Count | Should -BeGreaterThan 0
    }

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

Describe 'Persistent .NET example validation' -Tag 'Unit' {
    BeforeAll {
        $json = & yq -o=json '.' (Join-Path $repositoryRoot '.github/workflows/ci.yml')
        if ($LASTEXITCODE -ne 0) { throw 'CI workflow could not be parsed.' }
        $workflow = ($json -join "`n") | ConvertFrom-Json -AsHashtable
        $fixtureRelativePath = '.github/skills/dotnet-performance/examples/utf8-count'
        $fixtureRoot = Join-Path $repositoryRoot $fixtureRelativePath
    }

    It 'runs the correct runner from its discovery root and gates release without benchmarking' {
        $job = $workflow.jobs['dotnet-examples']
        $job.'runs-on' | Should -Be 'ubuntu-24.04'
        $job.permissions.contents | Should -Be 'read'
        $job.defaults.run.'working-directory' | Should -Be $fixtureRelativePath
        $job.ContainsKey('if') | Should -BeFalse
        $workflow.jobs.release.needs | Should -Contain 'dotnet-examples'
        ($job.steps | Where-Object { $_.ContainsKey('uses') -and $_.uses -like 'actions/setup-dotnet@*' }).with.'dotnet-version' |
            Should -Be '10.0.x'
        $runs = @($job.steps | Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_.run })
        $runs | Should -Contain 'dotnet build Example.CountParsing.slnx --configuration Release'
        $test = @($runs | Where-Object { $_ -match '^dotnet test ' })
        $test.Count | Should -Be 1
        $test[0] | Should -Match '--project src/Example.CountParsing.Tests/Example.CountParsing.Tests.csproj'
        $test[0] | Should -Match '--no-build'
        $test[0] | Should -Match '--filter-trait "Category=Parsing"'
        $source = Get-Content -LiteralPath (Join-Path $fixtureRoot 'src/Example.CountParsing.Tests/Tests/Unit/CountParserTests.cs') -Raw
        $count = [regex]::Matches($source, '\[InlineData\(').Count + [regex]::Matches($source, '\[Fact\]').Count
        $test[0] | Should -Match "--minimum-expected-tests $count(?:\s|$)"
        ($runs -join "`n") | Should -Not -Match 'dotnet run|BenchmarkSwitcher|--filter "\*CountParsingBenchmarks'
        $global = Get-Content -LiteralPath (Join-Path $fixtureRoot 'global.json') -Raw | ConvertFrom-Json
        $global.test.runner | Should -Be 'Microsoft.Testing.Platform'
    }

    It 'updates only the maintained runnable package root, not illustrative package fragments' {
        $json = & yq -o=json '.' (Join-Path $repositoryRoot '.github/dependabot.yml')
        $LASTEXITCODE | Should -Be 0
        $dependabot = ($json -join "`n") | ConvertFrom-Json -AsHashtable
        $nuget = @($dependabot.updates | Where-Object { $_.'package-ecosystem' -eq 'nuget' })
        $nuget.Count | Should -Be 1
        $nuget[0].directory | Should -Be "/$fixtureRelativePath"
        Join-Path $fixtureRoot 'Directory.Packages.props' | Should -Exist
    }
}
