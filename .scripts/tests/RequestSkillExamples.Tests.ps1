#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $skillsRoot = Join-Path $PSScriptRoot '../../.github/skills'
}

Describe 'REST collection example' -Tag 'Unit' {
    BeforeAll {
        $collection = Get-Content -LiteralPath (Join-Path $skillsRoot 'tooling-rest-client/assets/collection.http') -Raw
        $dotenv = Get-Content -LiteralPath (Join-Path $skillsRoot 'tooling-rest-client/assets/collection.env.example') -Raw
    }

    It 'uses exactly the declared dotenv inputs without literal authentication or response chaining' {
        $references = @([regex]::Matches($collection, '\{\{\$dotenv (\w+)\}\}') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $keys = @([regex]::Matches($dotenv, '(?m)^(\w+)=') | ForEach-Object { $_.Groups[1].Value })
        $keys | Should -Be $references
        $keys | Should -Be @('EXAMPLE_BASE_URL')
        $collection | Should -Not -Match '(?im)^Authorization:|\.response\.'
        $dotenv.Trim() | Should -Be 'EXAMPLE_BASE_URL=https://api.example.com'
    }

    It 'separates read and explicitly noted mutation with unique names and synthetic body' {
        $names = @([regex]::Matches($collection, '(?m)^# @name (\w+)') | ForEach-Object { $_.Groups[1].Value })
        $names | Should -Be @('getWidget', 'createWidget')
        [regex]::Matches($collection, '(?m)^(GET|POST) .+ HTTP/1\.1\r?$').Count | Should -Be 2
        $post = @($collection -split '(?m)^### ' | Where-Object { $_ -match '(?m)^POST ' })
        $post.Count | Should -Be 1
        $post[0] | Should -Match '(?m)^# @note Mutates server state'
        $body = [regex]::Match($post[0], '(?s)\r?\n\r?\n(\{.*\})').Groups[1].Value | ConvertFrom-Json
        $body.name | Should -Be 'example-widget'
        @($body.PSObject.Properties).Count | Should -Be 1
    }
}

Describe 'Bounded Web API example' -Tag 'Unit' {
    It 'extends the existing create action with explicit outcomes rather than a second scaffold' {
        $example = Get-Content -LiteralPath (Join-Path $skillsRoot 'dotnet-webapi/examples/typed-outcomes.md') -Raw
        $example | Should -Match 'Results<CreatedAtRoute<WidgetResponse>, ValidationProblem, Conflict<ProblemDetails>>'
        $example | Should -Match 'TypedResults.ValidationProblem\(invalid.Errors\)'
        $example | Should -Match 'Status = StatusCodes.Status409Conflict'
        $example | Should -Match 'application/json.*Conflict<ProblemDetails>'
        $example | Should -Not -Match 'catch \(Exception'
    }
}

Describe 'Retirement reporting example' -Tag 'Unit' {
    It 'keeps unverified mutation state distinct from archival and deletion' {
        $example = Get-Content -LiteralPath (Join-Path $skillsRoot 'github-repository-archive/examples/partial-retirement.md') -Raw
        $example | Should -Match 'one verified archive, one blocked before archival, one unverified outcome'
        $example | Should -Match 'Local clones and workspace entries: untouched'
        $example | Should -Match 'unresolved alerts are not described as fixed'
        $example | Should -Not -Match 'gh api --method|Remove-Item|kubectl delete'
    }
}
