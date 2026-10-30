#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $skillsRoot = Join-Path $PSScriptRoot '../../.github/skills'
    $performanceRoot = Join-Path $skillsRoot 'dotnet-performance/examples/utf8-count'
    $releaseRoot = Join-Path $skillsRoot 'dotnet-release-train'
    $workflowRoot = Join-Path $skillsRoot 'docs-readme/examples/reusable-workflow'
    $json = & yq -o=json '.' (Join-Path $workflowRoot '_report-label.yml.tmpl')
    if ($LASTEXITCODE -ne 0) { throw 'The workflow example is not valid YAML.' }
    $workflow = ($json -join "`n") | ConvertFrom-Json -AsHashtable
}

Describe 'Performance example structure' -Tag 'Unit' {
    It 'keeps the library source-only and includes all projects in the solution' {
        $properties = [xml](Get-Content -LiteralPath (Join-Path $performanceRoot 'Directory.Build.props') -Raw)
        $properties.Project.PropertyGroup.TargetFramework | Should -Be 'net10.0'
        $properties.Project.PropertyGroup.IsPackable | Should -Be 'false'
        $solution = [xml](Get-Content -LiteralPath (Join-Path $performanceRoot 'Example.CountParsing.slnx') -Raw)
        $solution.Solution.Folder.Project.Count | Should -Be 3
        foreach ($project in $solution.Solution.Folder.Project) {
            $path = Join-Path $performanceRoot $project.Path
            $path | Should -Exist
            Join-Path (Split-Path $path -Parent) 'README.md' | Should -Exist
        }
    }

    It 'keeps the documented case count in step with the self-contained test data' {
        $source = Get-Content -LiteralPath (Join-Path $performanceRoot 'src/Example.CountParsing.Tests/Tests/Unit/CountParserTests.cs') -Raw
        $caseCount = [regex]::Matches($source, '\[InlineData\(').Count + [regex]::Matches($source, '\[Fact\]').Count
        $caseCount | Should -Be 16
        $readme = Get-Content -LiteralPath (Join-Path $performanceRoot 'src/Example.CountParsing.Tests/README.md') -Raw
        $readme | Should -Match "$caseCount cases"
        $source | Should -Not -Match 'https?://|HttpClient'
    }

    It 'preserves the benchmark harness requirements and explicit failure reporting' {
        $source = Get-Content -LiteralPath (Join-Path $performanceRoot 'src/Example.CountParsing.Benchmarks/CountParsingBenchmarks.cs') -Raw
        $program = Get-Content -LiteralPath (Join-Path $performanceRoot 'src/Example.CountParsing.Benchmarks/Program.cs') -Raw
        $source | Should -Match 'public class CountParsingBenchmarks'
        $source | Should -Match '\[MemoryDiagnoser\]'
        $source | Should -Match '\[GlobalSetup\]'
        $program | Should -Match 'WithPowerPlan\(PowerPlan.UserPowerPlan\)'
        $program | Should -Match 'HasCriticalValidationErrors'
        $program | Should -Match 'report.ResultStatistics is null'
        $program | Should -Match 'return 1;'
    }
}

Describe 'Release reference example' -Tag 'Unit' {
    It 'selects complete mutually exclusive source and package graphs' {
        $project = [xml](Get-Content -LiteralPath (Join-Path $releaseRoot 'templates/Example.Consumer.csproj.tmpl') -Raw)
        $packages = [xml](Get-Content -LiteralPath (Join-Path $releaseRoot 'templates/Directory.Packages.props') -Raw)
        $source = $project.Project.ItemGroup | Where-Object { $_.HasChildNodes -and $_.FirstChild.Name -eq 'ProjectReference' }
        $binary = $project.Project.ItemGroup | Where-Object { $_.HasChildNodes -and $_.FirstChild.Name -eq 'PackageReference' }
        $source.Condition | Should -Be "'`$(Configuration)' == 'Debug'"
        $binary.Condition | Should -Be "'`$(Configuration)' != 'Debug'"
        $source.ProjectReference.Count | Should -Be 2
        $binary.PackageReference.Count | Should -Be 2
        @($binary.PackageReference.Include | Sort-Object) | Should -Be @('Example.Core', 'Example.Json')
        @($packages.Project.ItemGroup.PackageVersion.Version | Sort-Object -Unique) | Should -Be @('1.2.3')
        foreach ($reference in $binary.PackageReference) {
            $reference.HasAttribute('Version') | Should -BeFalse
            @($packages.Project.ItemGroup.PackageVersion | Where-Object Include -eq $reference.Include).Count | Should -Be 1
        }
    }
}

Describe 'Completed README workflow example' -Tag 'Unit' {
    It 'keeps the README caller valid and connected to the source workflow' {
        $readme = Get-Content -LiteralPath (Join-Path $workflowRoot 'README.md') -Raw
        $match = [regex]::Match($readme, '(?ms)```yaml\r?\n(.*?)^```')
        $match.Success | Should -BeTrue
        $path = Join-Path $TestDrive 'caller.yml'
        [IO.File]::WriteAllText($path, $match.Groups[1].Value)
        $json = & yq -o=json '.' $path
        $LASTEXITCODE | Should -Be 0
        $caller = ($json -join "`n") | ConvertFrom-Json -AsHashtable
        $caller.jobs.label.uses | Should -Be './.github/workflows/_report-label.yml'
        $caller.jobs.label.with.mode | Should -Be 'detailed'
        $caller.jobs.show.needs | Should -Be 'label'
        $caller.jobs.show.steps[0].env.REPORT_LABEL | Should -Be '${{ needs.label.outputs.label }}'
        $caller.permissions.Count | Should -Be 0
    }

    It 'connects typed inputs and every output layer without permissions or secret consumers' {
        $call = $workflow.on.workflow_call
        $call.inputs.mode.type | Should -Be 'string'
        $call.inputs.mode.default | Should -Be 'summary'
        $call.inputs.'runs-on'.default | Should -Be 'ubuntu-24.04'
        $call.outputs.label.value | Should -Be '${{ jobs.label.outputs.label }}'
        $workflow.jobs.label.outputs.label | Should -Be '${{ steps.compose.outputs.label }}'
        $workflow.jobs.label.'runs-on' | Should -Be '${{ inputs.runs-on }}'
        $workflow.permissions.Count | Should -Be 0
        $workflow.jobs.label.permissions.Count | Should -Be 0
        $call.ContainsKey('secrets') | Should -BeFalse
        $workflow.jobs.label.steps.Count | Should -Be 1
        $workflow.jobs.label.steps[0].env.REPORT_MODE | Should -Be '${{ inputs.mode }}'
        $workflow.jobs.label.steps[0].run | Should -Not -Match '\$\{\{'
    }

    It 'produces <Expected> or rejects <Mode> without evaluating input as shell code' -TestCases @(
        @{ Mode = 'summary'; Expected = 'Summary'; Valid = $true }
        @{ Mode = 'detailed'; Expected = 'Detailed'; Valid = $true }
        @{ Mode = 'unknown'; Expected = ''; Valid = $false }
        @{ Mode = ''; Expected = ''; Valid = $false }
        @{ Mode = '$(touch unexpected)'; Expected = ''; Valid = $false }
    ) {
        param($Mode, $Expected, $Valid)
        $bash = if ($IsWindows) { Join-Path $env:ProgramFiles 'Git/bin/bash.exe' } else { (Get-Command bash).Source }
        $outputFile = Join-Path $TestDrive 'step-output'
        $scriptFile = Join-Path $TestDrive 'step.sh'
        if (Test-Path -LiteralPath $outputFile) { Remove-Item -LiteralPath $outputFile }
        $prefix = @'
if command -v cygpath >/dev/null 2>&1; then
  GITHUB_OUTPUT="$(cygpath -u "$GITHUB_OUTPUT")"
fi
'@
        [IO.File]::WriteAllText($scriptFile, ($prefix + "`n" + $workflow.jobs.label.steps[0].run).Replace("`r`n", "`n"))
        $previousMode = $env:REPORT_MODE
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:REPORT_MODE = $Mode
            $env:GITHUB_OUTPUT = $outputFile
            Push-Location -LiteralPath $TestDrive
            try { $output = & $bash --noprofile --norc $scriptFile 2>&1 }
            finally { Pop-Location }
            $code = $LASTEXITCODE
            if ($Valid) {
                $code | Should -Be 0
                (Get-Content -LiteralPath $outputFile -Raw).Trim() | Should -BeExactly "label=$Expected"
            }
            else {
                $code | Should -Not -Be 0
                "$output" | Should -Match 'Unsupported mode'
                $outputFile | Should -Not -Exist
            }
            Join-Path $TestDrive 'unexpected' | Should -Not -Exist
        }
        finally {
            $env:REPORT_MODE = $previousMode
            $env:GITHUB_OUTPUT = $previousOutput
        }
    }

    It 'fails explicitly when the runner output file is missing' {
        $bash = if ($IsWindows) { Join-Path $env:ProgramFiles 'Git/bin/bash.exe' } else { (Get-Command bash).Source }
        $scriptFile = Join-Path $TestDrive 'missing-output.sh'
        [IO.File]::WriteAllText($scriptFile, $workflow.jobs.label.steps[0].run.Replace("`r`n", "`n"))
        $previousMode = $env:REPORT_MODE
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:REPORT_MODE = 'summary'
            $env:GITHUB_OUTPUT = $null
            $output = & $bash --noprofile --norc $scriptFile 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            "$output" | Should -Match 'GITHUB_OUTPUT is required'
        }
        finally {
            $env:REPORT_MODE = $previousMode
            $env:GITHUB_OUTPUT = $previousOutput
        }
    }
}
