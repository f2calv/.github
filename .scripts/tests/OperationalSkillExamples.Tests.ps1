#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $skillsRoot = Join-Path $repositoryRoot '.github/skills'
    . (Join-Path $skillsRoot 'dotnet-cleanup/scripts/Test-DotNetSourceConventions.ps1')
    . (Join-Path $skillsRoot 'dotnet-cleanup/scripts/Set-DotNetLogTemplateCasing.ps1')
    . (Join-Path $skillsRoot 'github-repository-baseline/scripts/Set-RepositoryBaseline.ps1')
    $cleanup = Get-Content -LiteralPath (Join-Path $skillsRoot 'dotnet-cleanup/examples/findings-and-fixes.md') -Raw

    function Get-ExampleSnippet {
        param([string]$Heading)
        $pattern = '(?ms)^### ' + [regex]::Escape($Heading) + '\r?\n\r?\n```csharp\r?\n(.*?)^```'
        $match = [regex]::Match($cleanup, $pattern)
        if (-not $match.Success) { throw "Missing example snippet: $Heading" }
        return $match.Groups[1].Value.Replace("`r`n", "`n")
    }
}

Describe 'Completed submission examples' -Tag 'Unit' {
    It 'uses the bug form prefix, field ordering and honest unchecked submission checks' {
        $formJson = & yq -o=json '.' (Join-Path $repositoryRoot '.github/ISSUE_TEMPLATE/1-bug.yml')
        $LASTEXITCODE | Should -Be 0
        $form = ($formJson -join "`n") | ConvertFrom-Json
        $draft = Get-Content -LiteralPath (Join-Path $skillsRoot 'github-issues-and-pull-requests/examples/bug-report.md') -Raw
        $draft.StartsWith("# $($form.title)") | Should -BeTrue
        $headings = @([regex]::Matches($draft, '(?m)^### (.+)\r?$') | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") })
        $labels = @($form.body | Where-Object type -ne 'markdown' | ForEach-Object { $_.attributes.label })
        $headings | Should -Be $labels
        foreach ($option in ($form.body | Where-Object type -eq 'checkboxes').attributes.options) {
            $draft | Should -Match ([regex]::Escape("- [ ] $($option.label)"))
        }
        $draft | Should -Not -Match '\[x\]'
    }

    It 'retains the PR template headings and checklist statements without inventing a related issue' {
        $template = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/pull_request_template.md') -Raw
        $draft = Get-Content -LiteralPath (Join-Path $skillsRoot 'github-issues-and-pull-requests/examples/pull-request.md') -Raw
        $pattern = '(?m)^## (.+)\r?$'
        @([regex]::Matches($draft, $pattern) | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") }) |
            Should -Be @([regex]::Matches($template, $pattern) | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") })
        $pattern = '(?m)^- \[[ x]\] (.+)\r?$'
        @([regex]::Matches($draft, $pattern) | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") }) |
            Should -Be @([regex]::Matches($template, $pattern) | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") })
        $draft | Should -Match '(?m)^None:'
        $draft | Should -Match 'Not run: Markdown lint'
        $draft | Should -Match 'Pending: current-head required checks'
        $draft | Should -Not -Match 'Closes #'
    }
}

Describe 'Cleanup worked snippets' -Tag 'Unit' {
    It 'reports the demonstrated top-level violation and accepts the separated files' {
        $path = Join-Path $TestDrive 'Widget.cs'
        [IO.File]::WriteAllText($path, (Get-ExampleSnippet '`Widget.cs` before'))
        $file = [pscustomobject]@{ RelativePath = 'Widget.cs'; FullPath = $path }
        @(Get-LayoutFindings $file).Rule | Should -Contain 'OneTopLevelTypePerFile'
        [IO.File]::WriteAllText($path, (Get-ExampleSnippet '`Widget.cs` after'))
        @(Get-LayoutFindings $file) | Should -BeNullOrEmpty
        $options = Join-Path $TestDrive 'WidgetOptions.cs'
        [IO.File]::WriteAllText($options, (Get-ExampleSnippet '`Models/WidgetOptions.cs` after'))
        @(Get-LayoutFindings ([pscustomobject]@{ RelativePath = 'Models/WidgetOptions.cs'; FullPath = $options })) |
            Should -BeNullOrEmpty
    }

    It 'preserves preview bytes, applies only the documented casing change and is idempotent' {
        $script:logPath = Join-Path $TestDrive 'Logging.cs'
        $before = Get-ExampleSnippet 'Logging before'
        [IO.File]::WriteAllText($script:logPath, $before)
        Mock Get-TrackedLogSource { @([pscustomobject]@{ RelativePath = 'Logging.cs'; FullPath = $script:logPath }) }
        @(Set-LogTemplateCasing -RepositoryPath $TestDrive -Check).Count | Should -Be 1
        $null = Set-LogTemplateCasing -RepositoryPath $TestDrive -WhatIf
        [IO.File]::ReadAllText($script:logPath) | Should -BeExactly $before
        $changes = @(Set-LogTemplateCasing -RepositoryPath $TestDrive -Confirm:$false)
        $changes[0].Replacements | Should -Be 2
        [IO.File]::ReadAllText($script:logPath) | Should -BeExactly (Get-ExampleSnippet 'Logging after')
        @(Set-LogTemplateCasing -RepositoryPath $TestDrive -Confirm:$false).Count | Should -Be 0
    }

    It 'leaves the documented interpolation anti-pattern unchanged rather than claiming a fix' {
        $script:logPath = Join-Path $TestDrive 'Interpolated.cs'
        $before = Get-ExampleSnippet 'Interpolated logging is not automatically repaired'
        [IO.File]::WriteAllText($script:logPath, $before)
        Mock Get-TrackedLogSource { @([pscustomobject]@{ RelativePath = 'Interpolated.cs'; FullPath = $script:logPath }) }
        @(Set-LogTemplateCasing -RepositoryPath $TestDrive -Confirm:$false).Count | Should -Be 0
        [IO.File]::ReadAllText($script:logPath) | Should -BeExactly $before
    }
}

Describe 'Baseline policy and result examples' -Tag 'Unit' {
    BeforeAll {
        $baselineRoot = Join-Path $skillsRoot 'github-repository-baseline'
        $policy = Get-Content -LiteralPath (Join-Path $baselineRoot 'scripts/policies/default.json') -Raw | ConvertFrom-Json -Depth 100
        $override = Get-Content -LiteralPath (Join-Path $baselineRoot 'templates/required-checks.override.json') -Raw | ConvertFrom-Json
        $policy.rulesetOverrides = @($override)
        Mock Invoke-GhCommand { throw 'Example validation must not access GitHub.' }
        Mock Invoke-GhMutation { throw 'Example validation must not mutate GitHub.' }
    }

    It 'adds only the exact target override and preserves the default rules' {
        $ruleset = Get-DesiredRuleset -Policy $policy -RepositoryName 'owner/example' -Visibility private
        $ruleset.rules.type | Should -Be @('deletion', 'non_fast_forward', 'pull_request', 'required_status_checks')
        $checks = @($ruleset.rules | Where-Object type -eq 'required_status_checks')
        $checks.Count | Should -Be 1
        $checks[0].parameters.required_status_checks.context | Should -Be @('lint / lint', 'test')
        $checks[0].parameters.strict_required_status_checks_policy | Should -BeTrue
        $other = Get-DesiredRuleset -Policy $policy -RepositoryName 'owner/example-two' -Visibility public
        $other.rules.type | Should -Be @('deletion', 'non_fast_forward', 'pull_request')
        Should -Invoke Invoke-GhCommand -Times 0 -Exactly
        Should -Invoke Invoke-GhMutation -Times 0 -Exactly
    }

    It 'merges public checks into one status rule without leaking them into private repositories' {
        $withPublic = Copy-JsonObject $policy
        $withPublic.publicRepository.requiredStatusChecks = @('analysis', 'test')
        $public = Get-DesiredRuleset -Policy $withPublic -RepositoryName 'owner/example' -Visibility public
        $checks = @($public.rules | Where-Object type -eq 'required_status_checks')
        $checks.Count | Should -Be 1
        $checks[0].parameters.required_status_checks.context | Should -Be @('lint / lint', 'test', 'analysis')
        $private = Get-DesiredRuleset -Policy $withPublic -RepositoryName 'owner/example' -Visibility private
        ($private.rules | Where-Object type -eq 'required_status_checks').parameters.required_status_checks.context |
            Should -Be @('lint / lint', 'test')
    }

    It 'matches actual result fields and reports settings rather than repository success counts' {
        $rows = @(Get-Content -LiteralPath (Join-Path $baselineRoot 'examples/partial-results.json') -Raw | ConvertFrom-Json)
        $generated = [Collections.Generic.List[object]]::new()
        foreach ($row in $rows) {
            Add-BaselineResult -Results $generated -RepositoryName $row.Repository -Setting $row.Setting -Status $row.Status -Detail $row.Detail
        }
        ($generated.ToArray() | ConvertTo-Json -Depth 10) | Should -BeExactly ($rows | ConvertTo-Json -Depth 10)
        $rows.Count | Should -Be 5
        @($rows | Where-Object Status -eq 'Compliant').Count | Should -Be 2
        @($rows | Where-Object Status -eq 'Changed').Count | Should -Be 1
        @($rows | Where-Object Status -eq 'PlanGated').Count | Should -Be 1
        @($rows | Where-Object Status -in @('Drift', 'Failed')).Count | Should -Be 1
        @($rows.Repository | Sort-Object -Unique).Count | Should -Be 2
    }
}
