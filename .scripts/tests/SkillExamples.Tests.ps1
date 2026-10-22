#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $skillsRoot = Join-Path $PSScriptRoot '../../.github/skills'
    $exampleSkills = @('container-images', 'container-workflows', 'dotnet-test-platform', 'dotnet-mcp', 'leadership-election')
}

Describe 'Worked skill examples' -Tag 'Unit' {
    It 'links every example directly from its owning skill and resolves local documentation links' {
        foreach ($name in $exampleSkills) {
            $root = Join-Path $skillsRoot $name
            $skill = Get-Content -LiteralPath (Join-Path $root 'SKILL.md') -Raw
            foreach ($example in Get-ChildItem -LiteralPath (Join-Path $root 'examples') -Filter '*.md') {
                $skill | Should -Match ([regex]::Escape("./examples/$($example.Name)"))
                $text = Get-Content -LiteralPath $example.FullName -Raw
                foreach ($link in [regex]::Matches($text, '\]\((\.\.?/[^)#]+)(?:#[^)]*)?\)')) {
                    $target = Join-Path $example.DirectoryName $link.Groups[1].Value
                    Test-Path -LiteralPath $target | Should -BeTrue -Because $link.Value
                }
            }
        }
    }

    It 'keeps the MTP specimen internally consistent' {
        $text = Get-Content -LiteralPath (Join-Path $skillsRoot 'dotnet-test-platform/examples/minimal-mtp.md') -Raw
        $files = @{}
        foreach ($block in [regex]::Matches($text, '(?ms)^### `([^`]+)`\r?\n\r?\n```(?:json|xml|csharp)\r?\n(.*?)^```')) {
            $files[$block.Groups[1].Value] = $block.Groups[2].Value
        }
        $files.Count | Should -Be 7
        ($files['global.json'] | ConvertFrom-Json).test.runner | Should -Be 'Microsoft.Testing.Platform'
        $project = [xml]$files['src/Example.Tests/Example.Tests.csproj']
        $project.Project.PropertyGroup.OutputType | Should -Be 'Exe'
        $project.Project.PropertyGroup.IsTestProject | Should -Be 'true'
        $project.Project.PropertyGroup.UseMicrosoftTestingPlatformRunner | Should -Be 'true'
        $project.Project.PropertyGroup.TestingPlatformDotnetTestSupport | Should -Be 'true'
        $packages = [xml]$files['Directory.Packages.props']
        @($project.Project.ItemGroup.PackageReference.Include) | Should -Be @('xunit.v3', 'Microsoft.Testing.Extensions.CodeCoverage')
        foreach ($reference in $project.Project.ItemGroup.PackageReference) {
            $reference.HasAttribute('Version') | Should -BeFalse
            @($packages.Project.ItemGroup.PackageVersion | Where-Object Include -eq $reference.Include).Count | Should -Be 1
        }
        ([xml]$files['Example.slnx']).Solution.Folder.Project.Path | Should -Be 'src/Example.Tests/Example.Tests.csproj'
        ([xml]$files['Directory.Build.props']).Project.PropertyGroup.TreatWarningsAsErrors | Should -Be 'true'
        [regex]::Matches($files['src/Example.Tests/Tests/Unit/CountParsingTests.cs'], '\[InlineData\(').Count | Should -Be 3
    }
}
