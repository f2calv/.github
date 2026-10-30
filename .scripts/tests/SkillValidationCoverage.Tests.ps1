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
    $sharding = $runner.Find({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
            $node.Extent.Text.StartsWith('if ($Shard -ne ''all'')')
        }, $false)
    if ($null -eq $sharding) { throw 'Central test sharding block not found.' }
    $shardingCode = [scriptblock]::Create($sharding.Extent.Text.Replace('$PSScriptRoot', '$RunnerRoot'))
    $selectionGuard = $runner.Find({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
            $node.Extent.Text.StartsWith('if ($Shard -ne ''all'' -and $TestPath.Count -gt 0)')
        }, $false)
    if ($null -eq $selectionGuard) { throw 'Central shard/path guard not found.' }
    $selectionGuardCode = [scriptblock]::Create($selectionGuard.Extent.Text)
    $resultGuard = $runner.Find({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
            $node.Extent.Text.StartsWith('if ($result.Result')
        }, $true)
    if ($null -eq $resultGuard) { throw 'Central executed-test result guard not found.' }
    $resultGuardCode = [scriptblock]::Create($resultGuard.Clauses[0].Item1.Extent.Text)
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
        $paths | Should -Contain (Join-Path $repositoryRoot '.github/skills/tooling-pre-commit/scripts/tests')
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

    It 'partitions every discovered test file exactly once across CI shards' {
        $paths = @(& {
                param($RunnerRoot, $Code)
                $TestPath = @()
                . $Code
                $TestPath
            } $scriptsRoot $discoveryCode)
        $expected = @($paths | ForEach-Object {
                Get-ChildItem -LiteralPath $_ -Filter '*.Tests.ps1' -File -Recurse
            } | Select-Object -ExpandProperty FullName | Sort-Object -Unique)
        $selected = @(foreach ($name in @('workspace-install', 'version-preparation', 'remaining')) {
                & {
                    param($RunnerRoot, $Code, $Paths, $Shard)
                    $TestPath = $Paths
                    . $Code
                    $TestPath
                } $scriptsRoot $shardingCode $paths $name
            })
        $selected.Count | Should -Be $expected.Count
        @($selected | Sort-Object -Unique).Count | Should -Be $selected.Count
        @($selected | Sort-Object) | Should -Be $expected
    }

    It 'isolates the expensive <Shard> suite' -ForEach @(
        @{ Shard = 'workspace-install'; Filename = 'Invoke-WorkspaceInstall.Tests.ps1' }
        @{ Shard = 'version-preparation'; Filename = 'Invoke-VersionPreparation.Tests.ps1' }
    ) {
        $paths = @(& {
                param($RunnerRoot, $Discovery, $Selection, $Shard)
                $TestPath = @()
                . $Discovery
                . $Selection
                $TestPath
            } $scriptsRoot $discoveryCode $shardingCode $Shard)
        $paths.Count | Should -Be 1
        [IO.Path]::GetFileName($paths[0]) | Should -BeExactly $Filename
    }

    It 'rejects explicit paths combined with a named shard' {
        {
            & {
                param($Code)
                $Shard = 'remaining'
                $TestPath = @('synthetic.Tests.ps1')
                . $Code
            } $selectionGuardCode
        } | Should -Throw '*not both*'
    }

    It 'fails closed when a dedicated test file disappears from discovery' {
        {
            & {
                param($RunnerRoot, $Code, $Root)
                $Shard = 'remaining'
                $TestPath = @($Root)
                . $Code
            } $scriptsRoot $shardingCode $TestDrive
        } | Should -Throw '*missing from central discovery*'
    }

    It 'rejects failed or empty test execution: <Outcome>, <PassedCount> passed' -ForEach @(
        @{ Outcome = 'Passed'; PassedCount = 0; Reject = $true }
        @{ Outcome = 'Failed'; PassedCount = 1; Reject = $true }
        @{ Outcome = 'Failed'; PassedCount = 0; Reject = $true }
        @{ Outcome = 'Passed'; PassedCount = 1; Reject = $false }
    ) {
        $result = [pscustomobject]@{ Result = $Outcome; PassedCount = $PassedCount }
        (& $resultGuardCode) | Should -Be $Reject
    }

    It 'runs all shards independently and keeps the existing required fan-in' {
        $json = & yq -o=json '.' (Join-Path $repositoryRoot '.github/workflows/_skills-library-tests.yml')
        $LASTEXITCODE | Should -Be 0
        $workflow = ($json -join "`n") | ConvertFrom-Json -AsHashtable
        $job = $workflow.jobs.test
        $job.strategy.'fail-fast' | Should -BeFalse
        $job.strategy.matrix.shard | Should -Be @('workspace-install', 'version-preparation', 'remaining')
        $step = @($job.steps | Where-Object { $_.ContainsKey('env') -and $_.env.ContainsKey('TEST_SHARD') })
        $step.Count | Should -Be 1
        $step[0].env.TEST_SHARD | Should -BeExactly '${{ matrix.shard }}'
        $step[0].run | Should -BeExactly 'npm run test:ps -- -Shard "$TEST_SHARD"'
        $json = & yq -o=json '.' (Join-Path $repositoryRoot '.github/workflows/ci.yml')
        $LASTEXITCODE | Should -Be 0
        $ci = ($json -join "`n") | ConvertFrom-Json -AsHashtable
        $ci.jobs.test.needs | Should -Contain 'skills-library-tests'
        $ci.jobs.test['if'] | Should -Match 'always\(\)'
        $ci.jobs.test.steps[0].env.TEST_RESULT | Should -BeExactly '${{ needs.skills-library-tests.result }}'
        $ci.jobs.test.steps[0].run | Should -Match '-ne ''success'''
        $ci.jobs.release.needs | Should -Contain 'test'
    }
}

Describe 'Network evidence boundaries' -Tag 'Unit' {
    It 'keeps synthetic measurements distinct from failed client acceptance and actual network proof' {
        $path = Join-Path $repositoryRoot '.github/skills/network-unifi/examples/change-evidence.md'
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
        $job['if'] | Should -BeExactly "github.event_name != 'workflow_dispatch' || inputs.skill-delivery == 'off'"
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

    It 'runs .NET examples for <EventName> with skill delivery <DeliveryMode>: <ExpectedRun>' -TestCases @(
        @{ EventName = 'pull_request'; DeliveryMode = ''; ExpectedRun = $true }
        @{ EventName = 'pull_request'; DeliveryMode = 'off'; ExpectedRun = $true }
        @{ EventName = 'pull_request'; DeliveryMode = 'prepare'; ExpectedRun = $true }
        @{ EventName = 'pull_request'; DeliveryMode = 'build'; ExpectedRun = $true }
        @{ EventName = 'push'; DeliveryMode = ''; ExpectedRun = $true }
        @{ EventName = 'push'; DeliveryMode = 'off'; ExpectedRun = $true }
        @{ EventName = 'push'; DeliveryMode = 'prepare'; ExpectedRun = $true }
        @{ EventName = 'push'; DeliveryMode = 'build'; ExpectedRun = $true }
        @{ EventName = 'workflow_dispatch'; DeliveryMode = 'off'; ExpectedRun = $true }
        @{ EventName = 'workflow_dispatch'; DeliveryMode = 'prepare'; ExpectedRun = $false }
        @{ EventName = 'workflow_dispatch'; DeliveryMode = 'build'; ExpectedRun = $false }
    ) {
        param($EventName, $DeliveryMode, $ExpectedRun)
        $condition = [regex]::Match($workflow.jobs['dotnet-examples']['if'],
            "\Agithub\.event_name != '(?<ManualEvent>[^']+)' \|\| inputs\.skill-delivery == '(?<NormalMode>[^']+)'\z")
        $condition.Success | Should -BeTrue
        $shouldRun = ($EventName -cne $condition.Groups['ManualEvent'].Value) -or
            ($DeliveryMode -ceq $condition.Groups['NormalMode'].Value)
        $shouldRun | Should -Be $ExpectedRun
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
