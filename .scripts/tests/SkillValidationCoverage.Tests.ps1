#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
}

Describe 'PowerShell script test coverage' -Tag 'Unit' {
    It 'pairs every script with a <Name>.Tests.ps1 file' {
        Push-Location -LiteralPath $repositoryRoot
        try { $files = @(git ls-files --cached --others --exclude-standard -- '*.ps1' '*.psm1') }
        finally { Pop-Location }
        $tests = @($files | Where-Object { $_ -like '*.Tests.ps1' } | ForEach-Object { [IO.Path]::GetFileName($_) -replace '\.Tests\.ps1$', '' })
        # Test runners, shared helpers exercised through their callers, and test fixtures are exempt.
        $missing = @($files | Where-Object {
                $_ -notlike '*.Tests.ps1' -and $_ -notmatch '(^|/)tests/' -and
                [IO.Path]::GetFileName($_) -notin @('Invoke-Tests.ps1') -and $_ -notlike '*.Common.ps1'
            } | Where-Object { ([IO.Path]::GetFileNameWithoutExtension($_)) -notin $tests })
        $missing | Should -BeNullOrEmpty
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
