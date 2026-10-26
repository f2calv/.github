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

function Get-InventorySharedDocuments {
    param([string]$Root, [string]$Directory, [string[]]$Files)
    foreach ($filename in @('Directory.Build.props', 'Directory.Build.targets')) {
        $ancestor = $Directory
        while ($true) {
            $candidate = Join-Path $ancestor $filename
            $relative = [IO.Path]::GetRelativePath($Root, $candidate).Replace('\', '/')
            if ($relative -in $Files) {
                $null = Get-InventoryContainedFile $Root $relative
                [pscustomobject]@{ Path = $relative; Xml = (Read-ProjectInventoryXml $candidate); Shared = $true }
                break
            }
            if ($ancestor -eq $Root) { break }
            $ancestor = Split-Path $ancestor -Parent
        }
    }
}

function Get-InventoryDocuments {
    param([string]$Root, [string]$RelativePath, [string[]]$Files, [Xml.XmlDocument]$Document)
    $documents = [Collections.Generic.List[object]]::new()
    $directory = Split-Path (Join-Path $Root $RelativePath) -Parent
    foreach ($shared in Get-InventorySharedDocuments $Root $directory $Files) { $documents.Add($shared) }
    $documents.Add([pscustomobject]@{ Path = $RelativePath; Xml = $Document; Shared = $false })
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
        }
    }
    return $documents.ToArray()
}

function Test-InventoryConditionalNode {
    param([Xml.XmlNode]$Node)
    $parent = $Node
    while ($parent -is [Xml.XmlElement]) {
        if ($parent.HasAttribute('Condition') -or $parent.LocalName -in @('When','Otherwise','Target')) { return $true }
        $parent = $parent.ParentNode
    }
    return $false
}

function Get-InventoryPropertyDeclarations {
    param([object]$InputDocument)
    $names = @('TargetFramework','TargetFrameworks','OutputType','IsTestProject','IsPackable',
        'PackAsTool','AssemblyName','PackageId','RootNamespace','UseMicrosoftTestingPlatformRunner')
    foreach ($node in $InputDocument.Xml.SelectNodes('//*[local-name()="PropertyGroup"]/*') |
        Where-Object { $_.LocalName -in $names }) {
        [pscustomobject]@{
            Name = $node.LocalName; Value = $node.InnerText.Trim()
            Source = $InputDocument.Path; Conditional = (Test-InventoryConditionalNode $node); Shared = $InputDocument.Shared
        }
    }
}

function Get-InventoryMetadata {
    param([object[]]$Documents, [Collections.Generic.List[string]]$Notes)
    $declarations = [Collections.Generic.List[object]]::new()
    $packages = [Collections.Generic.List[string]]::new()
    foreach ($inputDocument in $Documents) {
        foreach ($declaration in Get-InventoryPropertyDeclarations $inputDocument) {
            $declarations.Add($declaration)
        }
        if ($inputDocument.Xml.SelectNodes('//*[local-name()="Import"]').Count -gt 0) {
            $notes.Add("Import conditions/expressions in $($inputDocument.Path) are not evaluated; literal in-repository imports are inspected.")
        }
        foreach ($node in $inputDocument.Xml.SelectNodes('//*[local-name()="PackageReference"]')) {
            if ($node.HasAttribute('Include')) { $packages.Add($node.GetAttribute('Include')) }
        }
    }
    return [pscustomobject]@{ Declarations = $declarations.ToArray(); Packages = $packages.ToArray() }
}

function Get-InventoryProjectReferences {
    param([string]$Root, [string]$Directory, [object[]]$Documents)
    foreach ($inputDocument in $Documents) {
        foreach ($node in $inputDocument.Xml.SelectNodes('//*[local-name()="ProjectReference"]')) {
            if (-not $node.HasAttribute('Include')) { continue }
            $include = $node.GetAttribute('Include')
            $ownerDirectory = Split-Path (Join-Path $Root $inputDocument.Path) -Parent
            $candidate = $include.Replace('$(MSBuildThisFileDirectory)', "$ownerDirectory$([IO.Path]::DirectorySeparatorChar)")
            $resolved = ''
            if ($candidate -notmatch '[$@%*?]') {
                $resolved = [IO.Path]::GetFullPath([IO.Path]::Combine($Directory, $candidate.Replace('\', [IO.Path]::DirectorySeparatorChar)))
            }
            [pscustomobject]@{ Include = $include; Source = $inputDocument.Path; ResolvedPath = $resolved }
        }
    }
}

function Get-InventoryOwnedSources {
    param([string]$Root, [string]$Directory, [string]$RelativePath, [string[]]$Files, [string[]]$ProjectPaths)
    $prefix = ([IO.Path]::GetRelativePath($Root, $Directory).Replace('\','/')).TrimEnd('/')
    if ($prefix -eq '.') { $prefix = '' }
    $nested = @($ProjectPaths | Where-Object { $_ -ne $RelativePath } | ForEach-Object {
            $folder = [IO.Path]::GetDirectoryName($_).Replace('\','/')
            if ($folder -and $folder -ne $prefix -and
                ($prefix -eq '' -or $folder.StartsWith("$prefix/", [StringComparison]::OrdinalIgnoreCase))) { "$folder/" }
        })
    return $Files | Where-Object {
            $_ -match '\.cs$' -and ($prefix -eq '' -or $_.StartsWith("$prefix/", [StringComparison]::OrdinalIgnoreCase))
        } | Where-Object {
            $file = $_
            @($nested | Where-Object { $file.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0
        }
}

function Get-InventorySourceSignals {
    param([string]$Root, [string[]]$SourcePaths, [Collections.Generic.List[string]]$Notes)
    $signals = [Collections.Generic.HashSet[string]]::new()
    $patterns = [ordered]@{
        'test-attributes' = '\[(?:Fact|Theory|TestMethod|Test|TestCase)(?:Attribute)?(?:\s*[\](])'
        'benchmarks' = 'BenchmarkSwitcher|BenchmarkRunner|\[Benchmark(?:Attribute)?(?:\s*[\](])'
        'entry-or-host-code' = '\b(?:WebApplication|Host)\.Create|\.RunAsync\(|\bstatic\s+(?:async\s+)?(?:void|Task|int)\s+Main\('
        'backend-code' = ':\s*(?:ControllerBase|BackgroundService|IBgFeature)\b|:\s*[^{;]+,\s*IBgFeature\b'
        'test-doubles' = '\b(?:class|record)\s+(?:Fake|Stub|Mock)\w+'
    }
    foreach ($source in $SourcePaths) {
        if ($source -match '(^|/)(bin|obj)/|\.g\.cs$|\.generated\.cs$') { continue }
        $sourcePath = Get-InventoryContainedFile $Root $source
        $sourceFile = Get-Item -LiteralPath $sourcePath
        if ($sourceFile.Length -gt 2MB) { $notes.Add("Source signal scan skipped oversized file: $source"); continue }
        $text = [IO.File]::ReadAllText($sourcePath)
        # This is a heuristic signal scan, not a C# parser or compiled-file graph.
        $text = [regex]::Replace($text, '(?s:/\*.*?\*/)|(?m:^\s*//[^\r\n]*$)', '')
        foreach ($signal in $patterns.Keys) {
            if ($text -match $patterns[$signal]) { $null = $signals.Add($signal) }
        }
    }
    return ,$signals
}

function Get-InventoryReadmeSignals {
    param([string]$Root, [string]$Directory, [string[]]$Files)
    $readmePath = Join-Path $Directory 'README.md'
    $relativeReadme = [IO.Path]::GetRelativePath($Root, $readmePath).Replace('\','/')
    if ($relativeReadme -in $Files) {
        $null = Get-InventoryContainedFile $Root $relativeReadme
        if ((Get-Item -LiteralPath $readmePath).Length -le 256KB) {
            $readme = [IO.File]::ReadAllText($readmePath)
            if ($readme -match '(?i)test(?:ing)? (?:companion|support|double)|canned|fake (?:client|provider)|in-memory.*(?:test|client)') { 'documented-test-support' }
            if ($readme -match '(?i)integration.test (?:host|application)|test.host|WebApplicationFactory') { 'documented-test-host' }
        }
    }
}

function Test-InventoryTestProject {
    param([hashtable]$Declared, [string[]]$Packages, [Collections.Generic.HashSet[string]]$Signals, [string]$Name)
    $testPackages = @($packages | Where-Object { $_ -in @('xunit','xunit.v3','MSTest.TestFramework','NUnit','TUnit','Microsoft.NET.Test.Sdk') })
    return ($Declared.ContainsKey('IsTestProject') -and $Declared.IsTestProject -eq 'true') -or
        ($testPackages.Count -gt 0 -and ($signals.Contains('test-attributes') -or $name -match '\.Tests$'))
}

function Test-InventoryExecutable {
    param([hashtable]$Declared, [string]$Sdk)
    return ($Declared.ContainsKey('OutputType') -and $Declared.OutputType -in @('Exe','WinExe')) -or
        ($Sdk -match 'Microsoft.NET.Sdk.Web' -and -not ($Declared.ContainsKey('OutputType') -and $Declared.OutputType -eq 'Library'))
}

function Get-InventoryExecutableRole {
    param([string]$Name, [string]$RelativePath, [string]$Sdk, [Collections.Generic.HashSet[string]]$Signals)
    if ($Name -match 'TestHost|IntegrationHost' -or $Signals.Contains('documented-test-host')) {
        return @{ Role = 'integration-test-host'; Evidence = 'Executable/web shape with test-host name or documentation.' }
    }
    if ($RelativePath -match '(?i)(^|/)(samples?|examples?|fixtures?)/') {
        return @{ Role = 'sample-application'; Evidence = 'Executable/web shape in a sample/example/fixture directory.' }
    }
    if ($Sdk -match 'Microsoft.NET.Sdk.BlazorWebAssembly') {
        return @{ Role = 'frontend-client'; Evidence = 'Blazor WebAssembly SDK; distinguish the browser client from its server host.' }
    }
    return @{ Role = 'application'; Evidence = 'Declared executable or Web SDK executable default; deployment intent is unverified.' }
}

function Get-InventoryPrimaryRole {
    param([string]$Name, [string]$RelativePath, [string]$Sdk, [Collections.Generic.HashSet[string]]$Signals,
        [string[]]$Packages, [bool]$IsTest, [bool]$Executable)
    if ($IsTest) {
        return @{ Role = 'test-suite'; Confidence = 'high'; Evidence = 'Test-project declaration or test framework plus test source/name.' }
    }
    if ($Signals.Contains('benchmarks') -and 'BenchmarkDotNet' -in $Packages) {
        return @{ Role = 'benchmark'; Confidence = 'high'; Evidence = 'BenchmarkDotNet reference and benchmark source.' }
    }
    if ($Executable) {
        return (Get-InventoryExecutableRole $Name $RelativePath $Sdk $Signals) + @{ Confidence = 'medium' }
    }
    if ($Sdk -match 'Microsoft.NET.Sdk.BlazorWebAssembly') {
        return @{ Role = 'frontend-client'; Confidence = 'medium'; Evidence = 'Blazor WebAssembly SDK; distinguish the browser client from its server host.' }
    }
    if ($Name -match '\.(Testing|Fixtures)$' -and ($Signals.Contains('test-doubles') -or $Signals.Contains('documented-test-support'))) {
        return @{ Role = 'test-support-library'; Confidence = 'medium'; Evidence = 'Testing name and reusable fake/support implementation or documentation, without test-suite evidence.' }
    }
    return @{ Role = 'class-library'; Confidence = 'medium'; Evidence = 'No direct executable or test-runner evidence; library role is provisional.' }
}

function Set-InventoryReviewNotes {
    param([string]$Name, [string]$Role, [string]$Confidence, [bool]$IsTest, [hashtable]$Declared,
        [object[]]$Declarations, [Collections.Generic.List[string]]$Notes)
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
    return $confidence
}

function Get-InventoryProjectFacts {
    param([string]$Root, [string]$RelativePath, [string[]]$Files, [string[]]$ProjectPaths)
    $path = Get-InventoryContainedFile $Root $RelativePath
    $document = Read-ProjectInventoryXml $path
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    $directory = Split-Path $path -Parent
    $documents = @(Get-InventoryDocuments $Root $RelativePath $Files $document)
    $notes = [Collections.Generic.List[string]]::new()
    $evidence = [Collections.Generic.List[string]]::new()
    $metadata = Get-InventoryMetadata $documents $notes
    $declarations = $metadata.Declarations
    $packages = $metadata.Packages
    $references = @(Get-InventoryProjectReferences $Root $directory $documents)
    $declared = @{}
    foreach ($item in $declarations | Where-Object { -not $_.Shared -and -not $_.Conditional -and $_.Value -notmatch '\$\(' }) {
        $declared[$item.Name] = $item.Value
    }
    $sdk = $document.DocumentElement.GetAttribute('Sdk')
    $sourcePaths = @(Get-InventoryOwnedSources $Root $directory $RelativePath $Files $ProjectPaths)
    $signals = Get-InventorySourceSignals $Root $sourcePaths $notes
    foreach ($signal in Get-InventoryReadmeSignals $Root $directory $Files) { $null = $signals.Add($signal) }
    $isTest = Test-InventoryTestProject $declared $packages $signals $name
    $executable = Test-InventoryExecutable $declared $sdk
    $classification = Get-InventoryPrimaryRole $name $RelativePath $sdk $signals $packages $isTest $executable
    $role = $classification.Role
    $confidence = $classification.Confidence
    $evidence.Add($classification.Evidence)
    if ($declared.ContainsKey('PackAsTool') -and $declared.PackAsTool -eq 'true' -and $executable -and -not $isTest) {
        $role = 'cli-tool'; $confidence = 'high'; $evidence.Add('Executable with PackAsTool=true (publication not verified).')
    }
    $confidence = Set-InventoryReviewNotes $name $role $confidence $isTest $declared $declarations $notes
    $folder = Split-Path $directory -Leaf
    if ($folder -cne $name) { $notes.Add('Project filename and containing folder differ (not necessarily a defect).') }
    if ($sourcePaths.Count -eq 0) { $notes.Add('No owned tracked C# source discovered; source may be generated or linked.') }
    return [pscustomobject]@{
        Repository = (Split-Path $Root -Leaf); RepositoryRoot = $Root; Project = $RelativePath
        FullPath = $path; Name = $name; Folder = $folder; Sdk = $sdk; Role = $role; Confidence = $confidence
        ReviewRequired = $true; Evidence = @($evidence); ReviewNotes = @($notes)
        Declarations = @($declarations); SharedBuildFiles = @($documents | Where-Object Shared | ForEach-Object Path)
        Packages = @($packages | Sort-Object -Unique); ProjectReferences = @($references)
        ReferencedBy = @(); Solutions = @(); SourceFileCount = $sourcePaths.Count; SourceSignals = @($signals | Sort-Object)
    }
}

function Add-InventorySolutions {
    param([string]$Root, [string[]]$Files, [object[]]$Projects)
    foreach ($solution in $Files | Where-Object { $_ -match '\.(slnx|sln)$' }) {
        $solutionPath = Get-InventoryContainedFile $Root $solution
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
            foreach ($project in $Projects | Where-Object FullPath -eq $memberPath) { $project.Solutions += $solution }
        }
    }
}

function Get-InventoryRepositoryFacts {
    param([string]$Root, [switch]$IncludeUntracked)
    $projects = [Collections.Generic.List[object]]::new()
    $arguments = @('ls-files','--cached','-z')
    if ($IncludeUntracked) { $arguments += @('--others','--exclude-standard') }
    $files = @(((Invoke-ProjectInventoryGit $Root $arguments) -join "`n").Split([char]0) |
        Where-Object { $_ } | Sort-Object -Unique)
    $paths = @($files | Where-Object { $_ -match '\.csproj$' })
    $missing = @($paths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf) })
    $existing = @($paths | Where-Object { $_ -notin $missing })
    $available = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf })
    foreach ($relative in $existing) {
        try { $projects.Add((Get-InventoryProjectFacts $Root $relative $available $existing)) }
        catch {
            throw [InvalidOperationException]::new("Cannot inventory project '$relative'. Check XML, file access and path containment; no build was executed.")
        }
    }
    Add-InventorySolutions $Root $available $projects.ToArray()
    return [pscustomobject]@{
        Repository = [pscustomobject]@{
            Root = $Root; ProjectCount = $existing.Count; MissingTrackedProjects = $missing
            IncludeUntracked = [bool]$IncludeUntracked
        }
        Projects = $projects.ToArray()
    }
}

function Set-InventoryIncomingReferences {
    param([object[]]$Projects)
    foreach ($consumer in $Projects) {
        foreach ($reference in $consumer.ProjectReferences) {
            foreach ($producer in $projects | Where-Object { $_.FullPath -eq $reference.ResolvedPath }) {
                $producer.ReferencedBy += "$($consumer.Repository)/$($consumer.Project)"
            }
        }
    }
}

function Get-InventoryApplicationDependencies {
    param([object[]]$Projects)
    $reachable = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $queue = [Collections.Generic.Queue[object]]::new()
    foreach ($app in $Projects | Where-Object Role -in @('application','cli-tool')) { $queue.Enqueue($app) }
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($reference in $current.ProjectReferences) {
            if (-not $reference.ResolvedPath -or -not $reachable.Add($reference.ResolvedPath)) { continue }
            foreach ($dependency in $projects | Where-Object FullPath -eq $reference.ResolvedPath) { $queue.Enqueue($dependency) }
        }
    }
    return ,$reachable
}

function Set-InventoryGraphRoles {
    param([object[]]$Projects, [Collections.Generic.HashSet[string]]$Reachable)
    foreach ($project in $Projects) {
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
        $inventory = Get-InventoryRepositoryFacts $root -IncludeUntracked:$IncludeUntracked
        $repositories.Add($inventory.Repository)
        foreach ($project in $inventory.Projects) { $projects.Add($project) }
    }
    Set-InventoryIncomingReferences $projects.ToArray()
    $reachable = Get-InventoryApplicationDependencies $projects.ToArray()
    Set-InventoryGraphRoles $projects.ToArray() $reachable
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
