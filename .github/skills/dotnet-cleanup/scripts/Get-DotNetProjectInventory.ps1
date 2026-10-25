#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Inventories C# project roles from static evidence in explicitly selected Git worktrees.
.DESCRIPTION
    Reads project XML, nearest shared build files, tracked source paths and project references.
    Returns a JSON-compatible report with provisional roles, evidence and review flags. Never runs
    MSBuild, restores packages, builds, renames files or contacts remote services.
.PARAMETER RepositoryPath
    Explicit Git worktree roots. No parent-folder or adjacent-repository discovery is performed.
.PARAMETER IncludeUntracked
    Includes non-ignored untracked projects and source files alongside tracked working-tree files.
.EXAMPLE
    $report = & ./Get-DotNetProjectInventory.ps1 -RepositoryPath C:\work\example,C:\work\another
    $report.Projects | Format-Table Repository, Project, Role, Confidence
.NOTES
    Report paths and identities may be private. Keep exports local and review before publication.
    Static declarations are not evaluated MSBuild values or proof of deployment/publication.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$RepositoryPath,
    [switch]$IncludeUntracked
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-ProjectInventoryGit {
    param([string]$Root, [string[]]$Arguments)
    $output = @(& git -C $Root -c core.quotepath=false @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Project inventory Git command failed; verify the supplied worktree root and permissions.' }
    return $output
}

function Read-ProjectInventoryXml {
    param([string]$Path)
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 4MB
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try {
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    }
    finally { $reader.Dispose() }
}

function Get-InventoryContainedFile {
    param([string]$Root, [string]$RelativePath)
    $full = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $relative = [IO.Path]::GetRelativePath($Root, $full)
    if ($relative -eq '..' -or $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)") -or [IO.Path]::IsPathRooted($relative)) {
        throw 'Inventory input escapes the selected repository.'
    }
    $current = $Root
    foreach ($part in $relative.Split([IO.Path]::DirectorySeparatorChar)) {
        $current = Join-Path $current $part
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Inventory does not follow symbolic links or reparse points.'
        }
    }
    return $full
}

function Get-InventoryProjectFacts {
    param([string]$Root, [string]$RelativePath, [string[]]$Files, [string[]]$ProjectPaths)
    $path = Get-InventoryContainedFile $Root $RelativePath
    $document = Read-ProjectInventoryXml $path
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    $directory = Split-Path $path -Parent
    $declarations = [Collections.Generic.List[object]]::new()
    $notes = [Collections.Generic.List[string]]::new()
    $evidence = [Collections.Generic.List[string]]::new()
    $references = [Collections.Generic.List[object]]::new()
    $packages = [Collections.Generic.List[string]]::new()
    $documents = [Collections.Generic.List[object]]::new()
    $sharedPaths = [Collections.Generic.List[string]]::new()
    foreach ($filename in @('Directory.Build.props', 'Directory.Build.targets')) {
        $ancestor = $directory
        while ($true) {
            $candidate = Join-Path $ancestor $filename
            $relative = [IO.Path]::GetRelativePath($Root, $candidate).Replace('\', '/')
            if ($relative -in $Files) {
                $null = Get-InventoryContainedFile $Root $relative
                $documents.Add([pscustomobject]@{ Path = $relative; Xml = (Read-ProjectInventoryXml $candidate); Shared = $true })
                $sharedPaths.Add($relative)
                break
            }
            if ($ancestor -eq $Root) { break }
            $ancestor = Split-Path $ancestor -Parent
        }
    }
    $documents.Add([pscustomobject]@{ Path = $RelativePath; Xml = $document; Shared = $false })
    $loaded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($inputDocument in $documents) { $null = $loaded.Add($inputDocument.Path) }
    for ($index = 0; $index -lt $documents.Count; $index++) {
        $inputDocument = $documents[$index]
        foreach ($import in $inputDocument.Xml.SelectNodes('//*[local-name()="Import"]')) {
            $importPath = $import.GetAttribute('Project')
            $ownerDirectory = Split-Path (Join-Path $Root $inputDocument.Path) -Parent
            $importPath = $importPath.Replace('$(MSBuildThisFileDirectory)', "$ownerDirectory$([IO.Path]::DirectorySeparatorChar)")
            if (-not $importPath -or $importPath -match '[$@%*?]') { continue }
            $resolved = [IO.Path]::GetFullPath([IO.Path]::Combine($ownerDirectory, $importPath.Replace('\', [IO.Path]::DirectorySeparatorChar)))
            $relativeImport = [IO.Path]::GetRelativePath($Root, $resolved).Replace('\','/')
            if ($relativeImport -notin $Files -or -not $loaded.Add($relativeImport)) { continue }
            $null = Get-InventoryContainedFile $Root $relativeImport
            $documents.Add([pscustomobject]@{ Path = $relativeImport; Xml = (Read-ProjectInventoryXml $resolved); Shared = $true })
            $sharedPaths.Add($relativeImport)
        }
    }
    foreach ($inputDocument in $documents) {
        foreach ($node in $inputDocument.Xml.SelectNodes('//*[local-name()="PropertyGroup"]/*')) {
            if ($node.LocalName -notin @('TargetFramework','TargetFrameworks','OutputType','IsTestProject','IsPackable',
                    'PackAsTool','AssemblyName','PackageId','RootNamespace','UseMicrosoftTestingPlatformRunner')) { continue }
            $conditioned = $false
            $parent = $node
            while ($parent -is [Xml.XmlElement]) {
                if ($parent.HasAttribute('Condition') -or $parent.LocalName -in @('When','Otherwise','Target')) { $conditioned = $true }
                $parent = $parent.ParentNode
            }
            $declarations.Add([pscustomobject]@{
                    Name = $node.LocalName; Value = $node.InnerText.Trim()
                    Source = $inputDocument.Path; Conditional = $conditioned; Shared = $inputDocument.Shared
                })
        }
        if ($inputDocument.Xml.SelectNodes('//*[local-name()="Import"]').Count -gt 0) {
            $notes.Add("Import conditions/expressions in $($inputDocument.Path) are not evaluated; literal in-repository imports are inspected.")
        }
        foreach ($node in $inputDocument.Xml.SelectNodes('//*[local-name()="PackageReference"]')) {
            if ($node.HasAttribute('Include')) { $packages.Add($node.GetAttribute('Include')) }
        }
    }
    foreach ($inputDocument in $documents) {
        foreach ($node in $inputDocument.Xml.SelectNodes('//*[local-name()="ProjectReference"]')) {
            if (-not $node.HasAttribute('Include')) { continue }
            $include = $node.GetAttribute('Include')
            $ownerDirectory = Split-Path (Join-Path $Root $inputDocument.Path) -Parent
            $candidate = $include.Replace('$(MSBuildThisFileDirectory)', "$ownerDirectory$([IO.Path]::DirectorySeparatorChar)")
            $resolved = ''
            if ($candidate -notmatch '[$@%*?]') {
                $resolved = [IO.Path]::GetFullPath([IO.Path]::Combine($directory, $candidate.Replace('\', [IO.Path]::DirectorySeparatorChar)))
            }
            $references.Add([pscustomobject]@{ Include = $include; Source = $inputDocument.Path; ResolvedPath = $resolved })
        }
    }
    $declared = @{}
    foreach ($item in $declarations | Where-Object { -not $_.Shared -and -not $_.Conditional -and $_.Value -notmatch '\$\(' }) {
        $declared[$item.Name] = $item.Value
    }
    $sdk = $document.DocumentElement.GetAttribute('Sdk')
    $prefix = ([IO.Path]::GetRelativePath($Root, $directory).Replace('\','/')).TrimEnd('/')
    if ($prefix -eq '.') { $prefix = '' }
    $nested = @($ProjectPaths | Where-Object { $_ -ne $RelativePath } | ForEach-Object {
            $folder = [IO.Path]::GetDirectoryName($_).Replace('\','/')
            if ($folder -and $folder -ne $prefix -and
                ($prefix -eq '' -or $folder.StartsWith("$prefix/", [StringComparison]::OrdinalIgnoreCase))) { "$folder/" }
        })
    $sourcePaths = @($Files | Where-Object {
            $_ -match '\.cs$' -and ($prefix -eq '' -or $_.StartsWith("$prefix/", [StringComparison]::OrdinalIgnoreCase))
        } | Where-Object {
            $file = $_
            @($nested | Where-Object { $file.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0
        })
    $signals = [Collections.Generic.HashSet[string]]::new()
    foreach ($source in $sourcePaths) {
        if ($source -match '(^|/)(bin|obj)/|\.g\.cs$|\.generated\.cs$') { continue }
        $sourcePath = Get-InventoryContainedFile $Root $source
        $sourceFile = Get-Item -LiteralPath $sourcePath
        if ($sourceFile.Length -gt 2MB) { $notes.Add("Source signal scan skipped oversized file: $source"); continue }
        $text = [IO.File]::ReadAllText($sourcePath)
        # This is a heuristic signal scan, not a C# parser or compiled-file graph.
        $text = [regex]::Replace($text, '(?s:/\*.*?\*/)|(?m:^\s*//[^\r\n]*$)', '')
        if ($text -match '\[(?:Fact|Theory|TestMethod|Test|TestCase)(?:Attribute)?(?:\s*[\](])') { $null = $signals.Add('test-attributes') }
        if ($text -match 'BenchmarkSwitcher|BenchmarkRunner|\[Benchmark(?:Attribute)?(?:\s*[\](])') { $null = $signals.Add('benchmarks') }
        if ($text -match '\b(?:WebApplication|Host)\.Create|\.RunAsync\(|\bstatic\s+(?:async\s+)?(?:void|Task|int)\s+Main\(') { $null = $signals.Add('entry-or-host-code') }
        if ($text -match ':\s*(?:ControllerBase|BackgroundService|IBgFeature)\b|:\s*[^{;]+,\s*IBgFeature\b') {
            $null = $signals.Add('backend-code')
        }
        if ($text -match '\b(?:class|record)\s+(?:Fake|Stub|Mock)\w+') { $null = $signals.Add('test-doubles') }
    }
    $readmePath = Join-Path $directory 'README.md'
    $relativeReadme = [IO.Path]::GetRelativePath($Root, $readmePath).Replace('\','/')
    if ($relativeReadme -in $Files) {
        $null = Get-InventoryContainedFile $Root $relativeReadme
        if ((Get-Item -LiteralPath $readmePath).Length -le 256KB) {
            $readme = [IO.File]::ReadAllText($readmePath)
            if ($readme -match '(?i)test(?:ing)? (?:companion|support|double)|canned|fake (?:client|provider)|in-memory.*(?:test|client)') { $null = $signals.Add('documented-test-support') }
            if ($readme -match '(?i)integration.test (?:host|application)|test.host|WebApplicationFactory') { $null = $signals.Add('documented-test-host') }
        }
    }
    $testPackages = @($packages | Where-Object { $_ -in @('xunit','xunit.v3','MSTest.TestFramework','NUnit','TUnit','Microsoft.NET.Test.Sdk') })
    $isTest = ($declared.ContainsKey('IsTestProject') -and $declared.IsTestProject -eq 'true') -or
        ($testPackages.Count -gt 0 -and ($signals.Contains('test-attributes') -or $name -match '\.Tests$'))
    $executable = ($declared.ContainsKey('OutputType') -and $declared.OutputType -in @('Exe','WinExe')) -or
        ($sdk -match 'Microsoft.NET.Sdk.Web' -and -not ($declared.ContainsKey('OutputType') -and $declared.OutputType -eq 'Library'))
    $role = 'class-library'
    $confidence = 'medium'
    if ($isTest) { $role = 'test-suite'; $confidence = 'high'; $evidence.Add('Test-project declaration or test framework plus test source/name.') }
    elseif ($signals.Contains('benchmarks') -and @($packages | Where-Object { $_ -eq 'BenchmarkDotNet' }).Count) {
        $role = 'benchmark'; $confidence = 'high'; $evidence.Add('BenchmarkDotNet reference and benchmark source.')
    }
    elseif ($executable -and ($name -match 'TestHost|IntegrationHost' -or $signals.Contains('documented-test-host'))) {
        $role = 'integration-test-host'; $evidence.Add('Executable/web shape with test-host name or documentation.')
    }
    elseif ($executable -and $RelativePath -match '(?i)(^|/)(samples?|examples?|fixtures?)/') {
        $role = 'sample-application'; $evidence.Add('Executable/web shape in a sample/example/fixture directory.')
    }
    elseif ($sdk -match 'Microsoft.NET.Sdk.BlazorWebAssembly') {
        $role = 'frontend-client'; $evidence.Add('Blazor WebAssembly SDK; distinguish the browser client from its server host.')
    }
    elseif ($executable) { $role = 'application'; $evidence.Add('Declared executable or Web SDK executable default; deployment intent is unverified.') }
    elseif ($name -match '\.(Testing|Fixtures)$' -and ($signals.Contains('test-doubles') -or $signals.Contains('documented-test-support'))) {
        $role = 'test-support-library'; $evidence.Add('Testing name and reusable fake/support implementation or documentation, without test-suite evidence.')
    }
    else { $evidence.Add('No direct executable or test-runner evidence; library role is provisional.') }
    if ($declared.ContainsKey('PackAsTool') -and $declared.PackAsTool -eq 'true' -and $executable -and -not $isTest) {
        $role = 'cli-tool'; $confidence = 'high'; $evidence.Add('Executable with PackAsTool=true (publication not verified).')
    }
    if ($name -match '\.Tests$' -and -not $isTest) { $notes.Add('Tests suffix without confirmed test-runner evidence.'); $confidence = 'low' }
    if ($declared.ContainsKey('IsTestProject') -and $declared.IsTestProject -eq 'false' -and $isTest) {
        $notes.Add('Explicit IsTestProject=false conflicts with runner/source hints; verify the project contract.'); $confidence = 'low'
    }
    if ($name -match '\.Testing$' -and $role -eq 'class-library') { $notes.Add('Testing suffix alone cannot distinguish support code from an integration host.') }
    if (@($declarations | Where-Object { $_.Conditional -and $_.Name -in @('OutputType','IsTestProject','PackAsTool') }).Count) {
        $notes.Add('Role-related conditional declarations require configuration-specific evaluation.'); $confidence = 'low'
    }
    if (@($declarations | Where-Object { $_.Shared -and $_.Name -in @('OutputType','IsTestProject','PackAsTool') }).Count) {
        $notes.Add('Shared role declarations are recorded, not applied as unconditional project facts.'); $confidence = 'low'
    }
    if ($notes.Count -gt 0 -and $confidence -eq 'high') { $confidence = 'medium' }
    $folder = Split-Path $directory -Leaf
    if ($folder -cne $name) { $notes.Add('Project filename and containing folder differ (not necessarily a defect).') }
    if ($sourcePaths.Count -eq 0) { $notes.Add('No owned tracked C# source discovered; source may be generated or linked.') }
    return [pscustomobject]@{
        Repository = (Split-Path $Root -Leaf); RepositoryRoot = $Root; Project = $RelativePath
        FullPath = $path; Name = $name; Folder = $folder; Sdk = $sdk; Role = $role; Confidence = $confidence
        ReviewRequired = $true; Evidence = @($evidence); ReviewNotes = @($notes)
        Declarations = @($declarations); SharedBuildFiles = @($sharedPaths)
        Packages = @($packages | Sort-Object -Unique); ProjectReferences = @($references)
        ReferencedBy = @(); Solutions = @(); SourceFileCount = $sourcePaths.Count; SourceSignals = @($signals | Sort-Object)
    }
}

function Get-DotNetProjectInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$RepositoryPath, [switch]$IncludeUntracked)
    $projects = [Collections.Generic.List[object]]::new()
    $repositories = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new(
        $(if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }))
    foreach ($inputRoot in $RepositoryPath) {
        $root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $inputRoot).Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $gitRoot = @(Invoke-ProjectInventoryGit $root @('rev-parse','--show-toplevel'))[0]
        if ([IO.Path]::GetFullPath($gitRoot) -ne $root) { throw 'Supply repository roots, not subdirectories.' }
        if (-not $seen.Add($root)) { continue }
        if (((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Repository roots must not be reparse points.' }
        $arguments = @('ls-files','--cached','-z')
        if ($IncludeUntracked) { $arguments += @('--others','--exclude-standard') }
        $files = @(((Invoke-ProjectInventoryGit $root $arguments) -join "`n").Split([char]0) |
            Where-Object { $_ } | Sort-Object -Unique)
        $paths = @($files | Where-Object { $_ -match '\.csproj$' })
        $missing = @($paths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf) })
        $existing = @($paths | Where-Object { $_ -notin $missing })
        $repositories.Add([pscustomobject]@{
                Root = $root; ProjectCount = $existing.Count; MissingTrackedProjects = $missing
                IncludeUntracked = [bool]$IncludeUntracked
            })
        $available = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf })
        foreach ($relative in $existing) {
            try { $projects.Add((Get-InventoryProjectFacts $root $relative $available $existing)) }
            catch {
                throw [InvalidOperationException]::new("Cannot inventory project '$relative'. Check XML, file access and path containment; no build was executed.")
            }
        }
        foreach ($solution in $available | Where-Object { $_ -match '\.(slnx|sln)$' }) {
            $solutionPath = Get-InventoryContainedFile $root $solution
            $members = if ($solution -match '\.slnx$') {
                $xml = Read-ProjectInventoryXml $solutionPath
                @($xml.SelectNodes('//*[local-name()="Project"]') | ForEach-Object { $_.GetAttribute('Path') })
            }
            else {
                @([regex]::Matches([IO.File]::ReadAllText($solutionPath), '(?m)^Project\("[^"]+"\)\s*=\s*"[^"]*",\s*"([^"]+\.csproj)"') |
                    ForEach-Object { $_.Groups[1].Value })
            }
            foreach ($member in $members) {
                $memberPath = [IO.Path]::GetFullPath([IO.Path]::Combine((Split-Path $solutionPath -Parent), $member.Replace('\', [IO.Path]::DirectorySeparatorChar)))
                foreach ($project in $projects | Where-Object FullPath -eq $memberPath) { $project.Solutions += $solution }
            }
        }
    }
    foreach ($consumer in $projects) {
        foreach ($reference in $consumer.ProjectReferences) {
            foreach ($producer in $projects | Where-Object { $_.FullPath -eq $reference.ResolvedPath }) {
                $producer.ReferencedBy += "$($consumer.Repository)/$($consumer.Project)"
            }
        }
    }
    $reachable = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $queue = [Collections.Generic.Queue[object]]::new()
    foreach ($app in $projects | Where-Object Role -in @('application','cli-tool')) { $queue.Enqueue($app) }
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($reference in $current.ProjectReferences) {
            if (-not $reference.ResolvedPath -or -not $reachable.Add($reference.ResolvedPath)) { continue }
            foreach ($dependency in $projects | Where-Object FullPath -eq $reference.ResolvedPath) { $queue.Enqueue($dependency) }
        }
    }
    foreach ($project in $projects) {
        $testConsumers = @($projects | Where-Object {
                $_.Role -eq 'test-suite' -and $project.FullPath -in @($_.ProjectReferences | ForEach-Object { $_.ResolvedPath })
            })
        if ($project.Role -eq 'class-library' -and $project.Name -match '\.(Testing|Fixtures)$' -and $testConsumers.Count -gt 0) {
            $project.Role = 'test-support-library'
            $project.Confidence = 'low'
            $project.Evidence += 'Testing/Fixtures name and incoming test-suite references.'
            $project.ReviewNotes += 'Confirm the support API manually; no fake/support source marker was identified.'
        }
        if ($project.Role -eq 'class-library' -and 'backend-code' -in $project.SourceSignals -and $reachable.Contains($project.FullPath)) {
            $project.Role = 'backend-library-candidate'
            $project.Evidence += 'Backend implementation signals in an application dependency closure; shared services still need architectural review.'
            $project.ReviewNotes += 'Backend name/ownership cannot be decided from hosting or controller symbols alone.'
        }
        $project.ReferencedBy = @($project.ReferencedBy | Sort-Object -Unique)
        $project.Solutions = @($project.Solutions | Sort-Object -Unique)
    }
    return [pscustomobject]@{
        SchemaVersion = 1; Analysis = 'Static, unevaluated; roles are review candidates, not rename instructions.'
        Repositories = @($repositories); Projects = @($projects | Sort-Object Repository,Project)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Get-DotNetProjectInventory -RepositoryPath $RepositoryPath -IncludeUntracked:$IncludeUntracked }
    catch {
        Write-Error -ErrorAction Continue "Project inventory failed: $($_.Exception.Message)"
        exit 1
    }
}
