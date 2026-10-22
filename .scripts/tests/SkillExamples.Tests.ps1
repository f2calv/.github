#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $skillsRoot = Join-Path $PSScriptRoot '../../.github/skills'
    $exampleSkills = @(Get-ChildItem -LiteralPath $skillsRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'examples') } |
        Select-Object -ExpandProperty Name)

    function Read-YamlExample {
        param([Parameter(Mandatory)][string]$Name)
        $path = Join-Path $skillsRoot "dependabot-management/templates/$Name"
        $json = & yq -o=json '.' $path
        if ($LASTEXITCODE -ne 0) { throw "Could not parse Dependabot template '$Name'." }
        return ($json -join "`n") | ConvertFrom-Json -AsHashtable
    }
}

Describe 'Dependabot examples' -Tag 'Unit' {
    It 'covers exactly the documented independent ecosystem roots without duplicate entries' {
        $config = Read-YamlExample 'multi-root.yml'
        $config.version | Should -Be 2
        $pairs = @(
            foreach ($entry in $config.updates) {
                $entry.ContainsKey('directory') -xor $entry.ContainsKey('directories') | Should -BeTrue
                $entry.schedule.interval | Should -Be 'weekly'
                $roots = if ($entry.ContainsKey('directory')) { @($entry.directory) } else { @($entry.directories) }
                foreach ($root in $roots) {
                    $root | Should -Match '^/'
                    "$($entry.'package-ecosystem')|$root"
                }
            }
        )
        @($pairs | Sort-Object) | Should -Be @(
            'docker|/.docker/web', 'docker|/.docker/worker',
            'github-actions|/', 'npm|/src/admin', 'npm|/src/web', 'nuget|/', 'pre-commit|/'
        )
        @($pairs | Sort-Object -Unique).Count | Should -Be $pairs.Count
        $nuget = $config.updates | Where-Object { $_.'package-ecosystem' -eq 'nuget' }
        $nuget.groups.extensions.patterns | Should -Be @('Microsoft.Extensions.*')
        $nuget.groups.extensions.'update-types' | Should -Be @('minor', 'patch')
        $nuget.ContainsKey('ignore') | Should -BeFalse
    }

    It 'connects the private feed to its consumer using only Dependabot secret references' {
        $config = Read-YamlExample 'private-nuget.yml'
        $config.version | Should -Be 2
        $config.updates.Count | Should -Be 1
        $config.updates[0].'package-ecosystem' | Should -Be 'nuget'
        $config.updates[0].directory | Should -Be '/'
        $config.updates[0].registries | Should -Be @('example-feed')
        $feed = $config.registries['example-feed']
        $feed.type | Should -Be 'nuget-feed'
        ([uri]$feed.url).Host | Should -Be 'packages.example.com'
        $feed.username | Should -Be '${{secrets.PRIVATE_NUGET_USERNAME}}'
        $feed.password | Should -Be '${{secrets.PRIVATE_NUGET_PASSWORD}}'
        $config.updates[0].ContainsKey('insecure-external-code-execution') | Should -BeFalse
    }
}

Describe 'Dev Container tooling example' -Tag 'Unit' {
    BeforeAll {
        $devTemplates = Join-Path $skillsRoot 'devcontainer/templates'
        $container = Get-Content -LiteralPath (Join-Path $devTemplates 'devcontainer.json') -Raw |
            ConvertFrom-Json -AsHashtable
        $extensions = Get-Content -LiteralPath (Join-Path $devTemplates 'extensions.json') -Raw |
            ConvertFrom-Json -AsHashtable
    }

    It 'has one runtime owner and matching host/container extension sets without privileged access' {
        $container.image | Should -Be 'mcr.microsoft.com/devcontainers/base:bookworm'
        $container.remoteUser | Should -Be 'vscode'
        @($container.features.Keys) | Should -Be @('ghcr.io/devcontainers/features/powershell:2')
        $feature = $container.features['ghcr.io/devcontainers/features/powershell:2']
        $feature.version | Should -Be '7.4'
        $feature.modules | Should -Be 'Pester==5.7.1'
        $feature.preserveHistory | Should -BeFalse
        @($container.customizations.vscode.extensions | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object) |
            Should -Be @($extensions.recommendations | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
        foreach ($key in @('build', 'dockerComposeFile', 'mounts', 'runArgs', 'privileged',
                'capAdd', 'securityOpt', 'initializeCommand', 'postStartCommand', 'postAttachCommand')) {
            $container.ContainsKey($key) | Should -BeFalse
        }
        $container.postCreateCommand | Should -Be 'pwsh -NoProfile -File ./.devcontainer/Show-ToolVersions.ps1'
    }

    It 'renders a parseable post-create script that verifies installed tools without running tests' {
        $target = Join-Path $TestDrive 'Show-ToolVersions.ps1'
        Copy-Item -LiteralPath (Join-Path $devTemplates 'Show-ToolVersions.ps1.tmpl') -Destination $target
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() })
        @($commands | Sort-Object -Unique) | Should -Be @('Import-Module', 'Set-StrictMode', 'Write-Host')
        $output = & pwsh -NoProfile -File $target
        $LASTEXITCODE | Should -Be 0
        "$output" | Should -Match 'PowerShell 7\.'
        "$output" | Should -Match 'Pester 5\.7\.1'
    }
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
