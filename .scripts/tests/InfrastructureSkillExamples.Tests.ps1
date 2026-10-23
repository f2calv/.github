#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $skillsRoot = Join-Path $PSScriptRoot '../../.github/skills'
    $PSNativeCommandUseErrorActionPreference = $false

    function Read-ExampleDocuments {
        param([Parameter(Mandatory)][string]$Path)
        $json = & yq eval-all -o=json -I=0 '[.] | map(select(. != null))' $Path
        if ($LASTEXITCODE -ne 0) { throw "Could not parse example YAML: $Path" }
        return ($json -join "`n") | ConvertFrom-Json -AsHashtable
    }

    function Invoke-ExampleHelm {
        param([Parameter(Mandatory)][string[]]$Arguments)
        $output = & helm @Arguments 2>&1
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = ($output | ForEach-Object { "$_" }) -join "`n"
        }
    }
}

Describe 'Single-cluster GitOps example' -Tag 'Unit' {
    BeforeAll {
        $gitopsRoot = Join-Path $skillsRoot 'gitops-repository-structure/templates/single-cluster'
        $rootPath = Join-Path $gitopsRoot 'src/bootstrap.yaml'
        $root = @(Read-ExampleDocuments $rootPath)[0]
        $discoveryPath = Join-Path $gitopsRoot $root.spec.source.path
        $children = @(Get-ChildItem -LiteralPath $discoveryPath -Recurse -Filter '*.yaml' |
            ForEach-Object { Read-ExampleDocuments $_.FullName })
        $projects = @{}
        foreach ($file in Get-ChildItem -LiteralPath $gitopsRoot -Recurse -Filter '*.yaml') {
            foreach ($document in @(Read-ExampleDocuments $file.FullName)) {
                if ($document.kind -eq 'AppProject') {
                    if ($projects.ContainsKey($document.metadata.name)) { throw 'Duplicate AppProject identity in the example.' }
                    $projects[$document.metadata.name] = $document
                }
            }
        }
    }

    It 'discovers only direct child Applications and never the root or raw resources' {
        $root.kind | Should -Be 'Application'
        $root.spec.source.path | Should -Be 'src/applications'
        $root.spec.source.directory.recurse | Should -BeTrue
        $rootPath.StartsWith($discoveryPath, [StringComparison]::Ordinal) | Should -BeFalse
        $children.Count | Should -Be 2
        @($children.metadata.name | Sort-Object -Unique) | Should -Be @('app-projects', 'example')
        foreach ($child in $children) {
            $child.kind | Should -Be 'Application'
            $child.metadata.namespace | Should -Be 'argocd'
            $child.spec.source.path | Should -Match '^src/resources/'
            Test-Path -LiteralPath (Join-Path $gitopsRoot $child.spec.source.path) -PathType Container | Should -BeTrue
        }
        $paths = @($children.spec.source.path)
        foreach ($left in $paths) {
            foreach ($right in $paths | Where-Object { $_ -ne $left }) {
                $left.StartsWith("$right/", [StringComparison]::Ordinal) | Should -BeFalse
            }
        }
    }

    It 'seeds the authorization chain before the project-management leaf and orders direct children' {
        $projects.Count | Should -Be 3
        foreach ($name in @('example-root', 'example-projects')) {
            Test-Path -LiteralPath (Join-Path $gitopsRoot "bootstrap/$name.yaml") | Should -BeTrue
        }
        $projectApp = $children | Where-Object { $_.metadata.name -eq 'app-projects' }
        $workloadApp = $children | Where-Object { $_.metadata.name -eq 'example' }
        $projectApp.spec.project | Should -Be 'example-projects'
        $workloadApp.spec.project | Should -Be 'example-workloads'
        [int]$projectApp.metadata.annotations.'argocd.argoproj.io/sync-wave' |
            Should -BeLessThan ([int]$workloadApp.metadata.annotations.'argocd.argoproj.io/sync-wave')
        $projects['example-root'].spec.namespaceResourceWhitelist[0].kind | Should -Be 'Application'
        $projects['example-projects'].spec.namespaceResourceWhitelist[0].kind | Should -Be 'AppProject'
        $projects['example-root'].spec.namespaceResourceWhitelist.Count | Should -Be 1
        $projects['example-projects'].spec.namespaceResourceWhitelist.Count | Should -Be 1
        $projects['example-root'].spec.clusterResourceWhitelist.Count | Should -Be 0
        $projects['example-projects'].spec.clusterResourceWhitelist.Count | Should -Be 0
    }

    It 'matches exact source/destination grants and keeps each leaf resource under one owner' {
        $identities = @()
        foreach ($app in @($root) + $children) {
            $project = $projects[$app.spec.project]
            $project | Should -Not -BeNullOrEmpty
            $app.spec.project | Should -Not -Be 'default'
            $project.spec.sourceRepos | Should -Be @('https://example.com/gitops.git')
            $project.spec.sourceRepos | Should -Contain $app.spec.source.repoURL
            $project.spec.destinations.Count | Should -Be 1
            $project.spec.destinations[0].namespace | Should -Be $app.spec.destination.namespace
            $project.spec.destinations[0].server | Should -Be $app.spec.destination.server
            $app.metadata.finalizers | Should -Contain 'resources-finalizer.argocd.argoproj.io'
            $app.spec.syncPolicy.automated.prune | Should -BeTrue
            $app.spec.syncPolicy.automated.selfHeal | Should -BeTrue
            foreach ($grant in $project.spec.namespaceResourceWhitelist) {
                $grant.group | Should -Not -Be '*'
                $grant.kind | Should -Not -Be '*'
            }
        }
        foreach ($app in $children) {
            $project = $projects[$app.spec.project]
            foreach ($file in Get-ChildItem -LiteralPath (Join-Path $gitopsRoot $app.spec.source.path) -Filter '*.yaml') {
                foreach ($resource in @(Read-ExampleDocuments $file.FullName)) {
                    $resource.metadata.namespace | Should -Be $app.spec.destination.namespace
                    $group = if ($resource.apiVersion.Contains('/')) { $resource.apiVersion.Split('/')[0] } else { '' }
                    @($project.spec.namespaceResourceWhitelist |
                        Where-Object { $_.group -eq $group -and $_.kind -eq $resource.kind }).Count | Should -Be 1
                    $identities += "$($resource.apiVersion)|$($resource.kind)|$($resource.metadata.namespace)|$($resource.metadata.name)"
                }
            }
        }
        @($identities | Sort-Object -Unique).Count | Should -Be $identities.Count
        $workload = $children | Where-Object { $_.metadata.name -eq 'example' }
        $workload.spec.syncPolicy.syncOptions | Should -Contain 'CreateNamespace=true'
        $projects['example-workloads'].spec.clusterResourceWhitelist.Count | Should -Be 1
        $projects['example-workloads'].spec.clusterResourceWhitelist[0].kind | Should -Be 'Namespace'
        $projects['example-workloads'].spec.namespaceResourceWhitelist.Count | Should -Be 1
        $projects['example-workloads'].spec.namespaceResourceWhitelist[0].kind | Should -Be 'ConfigMap'
    }
}

Describe 'Helm chart contract example' -Tag 'Unit' {
    BeforeAll {
        $chart = Join-Path $skillsRoot 'helm-charts/examples/example-message'
    }

    It 'lints and renders <Fixture> with the expected resource shape' -TestCases @(
        @{ Fixture = ''; Count = 1; Text = 'Hello from the Helm example' }
        @{ Fixture = 'ci/custom-values.yaml'; Count = 1; Text = 'Literal {{ not-a-template }}: "quoted"' }
        @{ Fixture = 'ci/disabled-values.yaml'; Count = 0; Text = '' }
    ) {
        param($Fixture, $Count, $Text)
        $valuesArguments = if ($Fixture) { @('--values', (Join-Path $chart $Fixture)) } else { @() }
        $lint = Invoke-ExampleHelm (@('lint', $chart, '--strict', '--kube-version', '1.32.0') + $valuesArguments)
        $lint.ExitCode | Should -Be 0 -Because $lint.Output
        $render = Invoke-ExampleHelm (@('template', 'example', $chart, '--namespace', 'example', '--kube-version', '1.32.0') + $valuesArguments)
        $render.ExitCode | Should -Be 0 -Because $render.Output
        $outputPath = Join-Path $TestDrive 'rendered.yaml'
        Set-Content -LiteralPath $outputPath -Value $render.Output
        $documents = @(Read-ExampleDocuments $outputPath)
        $documents.Count | Should -Be $Count
        if ($Count -eq 1) {
            $documents[0].apiVersion | Should -Be 'v1'
            $documents[0].kind | Should -Be 'ConfigMap'
            $documents[0].metadata.name | Should -Be 'example-message'
            $documents[0].metadata.namespace | Should -Be 'example'
            $documents[0].metadata.labels.'app.kubernetes.io/instance' | Should -Be 'example'
            $documents[0].metadata.labels.'helm.sh/chart' | Should -Be 'example-message-0.1.0'
            $documents[0].data.Count | Should -Be 1
            $documents[0].data.message | Should -BeExactly $Text
        }
    }

    It 'rejects <Fixture> during lint and rendering with a field-specific schema error' -TestCases @(
        @{ Fixture = 'empty-text.yaml'; Field = 'text' }
        @{ Fixture = 'string-boolean.yaml'; Field = 'enabled' }
        @{ Fixture = 'unknown-key.yaml'; Field = 'enabeld' }
    ) {
        param($Fixture, $Field)
        $values = Join-Path $chart "tests/invalid/$Fixture"
        foreach ($arguments in @(
                @('lint', $chart, '--strict', '--values', $values),
                @('template', 'example', $chart, '--namespace', 'example', '--values', $values))) {
            $result = Invoke-ExampleHelm $arguments
            $result.ExitCode | Should -Not -Be 0
            $result.Output | Should -Match $Field
            $result.Output | Should -Match 'schema'
        }
    }

    It 'enforces the text boundary at <Length> characters' -TestCases @(
        @{ Length = 1; Valid = $true }
        @{ Length = 256; Valid = $true }
        @{ Length = 257; Valid = $false }
    ) {
        param($Length, $Valid)
        $text = 'x' * $Length
        $result = Invoke-ExampleHelm @('template', 'example', $chart, '--namespace', 'example',
            '--set-string', "message.text=$text")
        if ($Valid) {
            $result.ExitCode | Should -Be 0 -Because $result.Output
            $outputPath = Join-Path $TestDrive 'boundary.yaml'
            Set-Content -LiteralPath $outputPath -Value $result.Output
            $document = @(Read-ExampleDocuments $outputPath)[0]
            $document.data.message | Should -BeExactly $text
        }
        else {
            $result.ExitCode | Should -Not -Be 0
            $result.Output | Should -Match 'text'
            $result.Output | Should -Match 'schema'
        }
    }

    It 'still rejects invalid latent values when the resource is disabled' {
        $result = Invoke-ExampleHelm @('template', 'example', $chart,
            '--values', (Join-Path $chart 'tests/invalid/empty-text.yaml'), '--set', 'message.enabled=false')
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'text'
        $result.Output | Should -Match 'schema'
    }

    It 'includes runtime files in the package and excludes all success/failure fixtures' {
        $result = Invoke-ExampleHelm @('package', $chart, '--destination', $TestDrive)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $package = Join-Path $TestDrive 'example-message-0.1.0.tgz'
        $package | Should -Exist
        Add-Type -AssemblyName System.Formats.Tar
        $fileStream = [IO.File]::OpenRead($package)
        $gzip = [IO.Compression.GZipStream]::new($fileStream, [IO.Compression.CompressionMode]::Decompress)
        $reader = [System.Formats.Tar.TarReader]::new($gzip)
        try {
            $names = @(while ($entry = $reader.GetNextEntry()) { $entry.Name })
            foreach ($name in @('Chart.yaml', 'values.yaml', 'values.schema.json', 'templates/configmap.yaml', 'README.md')) {
                $names | Should -Contain "example-message/$name"
            }
            @($names | Where-Object { $_ -match '(^|/)(ci|tests)(/|$)' }).Count | Should -Be 0
        }
        finally {
            $reader.Dispose()
            $gzip.Dispose()
            $fileStream.Dispose()
        }
    }

    It 'limits the generic YAML lint exclusion to the actual Go-template directory' {
        $config = @(Read-ExampleDocuments (Join-Path $PSScriptRoot '../../.pre-commit-config.yaml'))[0]
        $yamlHook = @($config.repos.hooks | Where-Object { $_.id -eq 'check-yaml' })[0]
        '.github/skills/helm-charts/examples/example-message/templates/configmap.yaml' | Should -Match $yamlHook.exclude
        '.github/skills/helm-charts/examples/example-message/values.yaml' | Should -Not -Match $yamlHook.exclude
        '.github/skills/gitops-repository-structure/templates/single-cluster/src/bootstrap.yaml' | Should -Not -Match $yamlHook.exclude
    }
}

Describe 'Parallel NGINX route example' -Tag 'Unit' {
    BeforeAll {
        $ingressRoot = Join-Path $skillsRoot 'nginx-ingress-migration/templates'
    }

    It 'uses distinct non-default class identities that match the route selection' {
        $sourceClass = @(Read-ExampleDocuments (Join-Path $ingressRoot 'source-class.expected.yaml'))[0]
        $targetClass = @(Read-ExampleDocuments (Join-Path $ingressRoot 'target-class.expected.yaml'))[0]
        $source = @(Read-ExampleDocuments (Join-Path $ingressRoot 'source-ingress.yaml'))[0]
        $target = @(Read-ExampleDocuments (Join-Path $ingressRoot 'target-ingress.yaml'))[0]
        $sourceClass.spec.controller | Should -Be 'k8s.io/ingress-nginx'
        $targetClass.spec.controller | Should -Be 'nginx.org/ingress-controller'
        $sourceClass.metadata.name | Should -Not -Be $targetClass.metadata.name
        $source.spec.ingressClassName | Should -Be $sourceClass.metadata.name
        $target.spec.ingressClassName | Should -Be $targetClass.metadata.name
        foreach ($class in @($sourceClass, $targetClass)) {
            $class.kind | Should -Be 'IngressClass'
            $class.metadata.annotations.'ingressclass.kubernetes.io/is-default-class' | Should -BeExactly 'false'
        }
    }

    It 'changes only the declared identity, class and annotation mappings' {
        $source = @(Read-ExampleDocuments (Join-Path $ingressRoot 'source-ingress.yaml'))[0]
        $target = @(Read-ExampleDocuments (Join-Path $ingressRoot 'target-ingress.yaml'))[0]
        $source.metadata.name | Should -Be 'example-route'
        $target.metadata.name | Should -Be 'example-route-f5-preview'
        $source.metadata.annotations.Count | Should -Be 3
        $target.metadata.annotations.Count | Should -Be 3
        $source.metadata.annotations.'nginx.ingress.kubernetes.io/proxy-body-size' | Should -BeExactly '8m'
        $target.metadata.annotations.'nginx.org/client-max-body-size' | Should -BeExactly '8m'
        foreach ($name in @('read', 'send')) {
            $source.metadata.annotations["nginx.ingress.kubernetes.io/proxy-$name-timeout"] | Should -BeExactly '45'
            $target.metadata.annotations["nginx.org/proxy-$name-timeout"] | Should -BeExactly '45s'
        }
        $target.metadata.name = $source.metadata.name
        $target.metadata.annotations = $source.metadata.annotations
        $target.spec.ingressClassName = $source.spec.ingressClassName
        ($target | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly ($source | ConvertTo-Json -Depth 20 -Compress)
        $source.metadata.namespace | Should -Be 'example'
        $source.spec.tls[0].secretName | Should -Be 'example-tls'
        $source.spec.rules[0].http.paths[0].backend.service.name | Should -Be 'example-api'
    }
}
