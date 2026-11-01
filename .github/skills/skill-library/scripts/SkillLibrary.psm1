#Requires -Version 7.4
Set-StrictMode -Version 3.0

$script:BootstrapId = 'skill'
$script:BootstrapPath = 'src/skill-library-extension'
$script:SchemaPath = Join-Path $PSScriptRoot '../skill-metadata.schema.json'
$script:VersionPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
$script:PluginSchema = 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
$script:PluginNamespace = 'io.github.f2calv.skill-library'
$script:PortableFrontmatter = @('name', 'description', 'license', 'compatibility', 'metadata', 'allowed-tools')
$script:SkillNamePattern = '^(?=.{1,64}$)[a-z0-9]+(-[a-z0-9]+)*$'
# specify init writes its own speckit-* skills into .github/skills; they are Spec Kit's, not ours to version or publish.
$script:SpecKitSkillPattern = 'speckit-*'
$script:CataloguePath = 'docs/skills.md'

function Invoke-SkillTool {
    param([Parameter(Mandatory)][string]$Name, [string[]]$Arguments = @(), [string]$WorkingDirectory = (Get-Location).Path)
    Push-Location -LiteralPath $WorkingDirectory
    try { $Output = & $Name @Arguments 2>&1 }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "$Name $($Arguments -join ' ') failed: $($Output -join "`n")" }
    return @($Output | ForEach-Object { "$_" })
}

function ConvertFrom-SkillYaml {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Yaml, [string]$Expression = '.')
    $Json = $Yaml | & yq -p=yaml -o=json $Expression
    if ($LASTEXITCODE -ne 0) { throw 'Invalid YAML.' }
    return ($Json -join "`n") | ConvertFrom-Json -AsHashtable
}

function Read-SkillYaml {
    param([Parameter(Mandatory)][string]$Path, [string]$Expression = '.')
    return ConvertFrom-SkillYaml -Yaml ([IO.File]::ReadAllText($Path)) -Expression $Expression
}

function Get-SkillFrontmatter {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Markdown)
    $Match = [regex]::Match($Markdown, '\A---\r?\n(.*?)\r?\n---\r?\n', 'Singleline')
    if (-not $Match.Success) { return @{} }
    return ConvertFrom-SkillYaml -Yaml $Match.Groups[1].Value
}

function ConvertTo-SkillPortableMarkdown {
    <# Moves client-specific frontmatter fields into metadata as strings so SKILL.md meets the Agent Skills specification. #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Markdown)
    $Match = [regex]::Match($Markdown, '\A---\r?\n(.*?)\r?\n---\r?\n', 'Singleline')
    if (-not $Match.Success) { return $Markdown }
    $Front = ConvertFrom-SkillYaml -Yaml $Match.Groups[1].Value
    $Moved = @($Front.Keys | Where-Object { $_ -notin $script:PortableFrontmatter })
    if (-not $Moved.Count) { return $Markdown }
    $Portable = [ordered]@{}
    foreach ($Key in $Front.Keys) { if ($Key -in $script:PortableFrontmatter -and $Key -ne 'metadata') { $Portable[$Key] = $Front[$Key] } }
    $Metadata = [ordered]@{}
    if ($Front.Contains('metadata') -and $Front['metadata'] -is [Collections.IDictionary]) {
        foreach ($Pair in $Front['metadata'].GetEnumerator()) { $Metadata[$Pair.Key] = $Pair.Value }
    }
    foreach ($Key in $Moved) {
        $Value = $Front[$Key]
        $Metadata[$Key] = if ($Value -is [bool]) { $Value.ToString().ToLowerInvariant() } else { [string]$Value }
    }
    $Portable['metadata'] = $Metadata
    return "---`n$(ConvertTo-SkillYamlText $Portable)---`n" + $Markdown.Substring($Match.Length)
}

function Test-SkillPortableFrontmatter {
    <# Returns Agent Skills specification errors for a SKILL.md after portable normalisation. #>
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][AllowEmptyString()][string]$Markdown)
    $Front = Get-SkillFrontmatter (ConvertTo-SkillPortableMarkdown $Markdown)
    $Name = [string]$Front['name']
    $Description = [string]$Front['description']
    $Errors = [Collections.Generic.List[string]]::new()
    if ($Name -cne $Id) { $Errors.Add("${Id}: SKILL.md name '$Name' must match the folder name.") }
    if ($Id -cnotmatch $script:SkillNamePattern) { $Errors.Add("${Id}: the folder name is not a valid Agent Skills name.") }
    if ($Description.Length -lt 1 -or $Description.Length -gt 1024) { $Errors.Add("${Id}: SKILL.md description must be 1-1024 characters.") }
    if ($Front.Contains('compatibility') -and ([string]$Front['compatibility']).Length -gt 500) { $Errors.Add("${Id}: SKILL.md compatibility exceeds 500 characters.") }
    if ($Front.Contains('metadata')) {
        if ($Front['metadata'] -isnot [Collections.IDictionary]) { $Errors.Add("${Id}: SKILL.md metadata must be a map.") }
        elseif (@($Front['metadata'].Values | Where-Object { $_ -isnot [string] }).Count) { $Errors.Add("${Id}: SKILL.md metadata values must be strings.") }
    }
    return @($Errors)
}

function ConvertTo-SkillVersion {
    param([string]$Version)
    if ($Version -cnotmatch $script:VersionPattern) { throw "Invalid version '$Version'." }
    return [version]$Version
}

function New-SkillComponent {
    param([string]$Id, [string]$Kind, [string]$Path, [string]$ManifestPath, [hashtable]$Metadata, [string]$Description)
    [pscustomobject]@{
        Id            = $Id
        Kind          = $Kind
        Path          = $Path
        ManifestPath  = $ManifestPath
        Metadata      = $Metadata
        Version       = [string]$Metadata.version
        Facets        = @($Metadata['facets'] ?? @())
        Required      = @($Metadata['required'] ?? @())
        Related       = @($Metadata['related'] ?? @())
        ExternalFiles = @($Metadata['externalFiles'] ?? @())
        Description   = $Description
    }
}

function Test-SkillIgnoredPath {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Path)
    $PSNativeCommandUseErrorActionPreference = $false
    $Output = @(& git -C $RepoRoot check-ignore --quiet -- $Path 2>&1)
    switch ($LASTEXITCODE) {
        0 { return $true }
        1 { return $false }
        default { throw "Cannot determine Git ignore status for '$Path': $($Output -join "`n"). Verify the repository root." }
    }
}

function Get-SkillComponent {
    <# Returns every skill with a sidecar plus the bootstrap extension. #>
    param([Parameter(Mandatory)][string]$RepoRoot)
    $Sidecars = @(Get-ChildItem -Path (Join-Path $RepoRoot '.github/skills/*/skill.metadata.yaml') -File | Sort-Object FullName)
    $Sidecars = @($Sidecars | Where-Object { $_.Directory.Name -notlike $script:SpecKitSkillPattern -and -not (Test-SkillIgnoredPath -RepoRoot $RepoRoot -Path $_.FullName) })
    $Components = foreach ($Sidecar in $Sidecars) {
        $Id = $Sidecar.Directory.Name
        $Front = Get-SkillFrontmatter ([IO.File]::ReadAllText((Join-Path $Sidecar.DirectoryName 'SKILL.md')))
        New-SkillComponent -Id $Id -Kind 'skill' -Path ".github/skills/$Id" -ManifestPath ".github/skills/$Id/skill.metadata.yaml" `
            -Metadata (Read-SkillYaml $Sidecar.FullName) -Description ([string]$Front['description'])
    }
    $Bootstrap = Join-Path $RepoRoot "$script:BootstrapPath/extension.yml"
    if (Test-Path -LiteralPath $Bootstrap) {
        $Manifest = Read-SkillYaml $Bootstrap
        $Components = @($Components) + (New-SkillComponent -Id $script:BootstrapId -Kind 'bootstrap' -Path $script:BootstrapPath `
                -ManifestPath "$script:BootstrapPath/extension.yml" -Metadata @{ version = $Manifest.extension.version } -Description $Manifest.extension.description)
    }
    return @($Components)
}

function Get-SkillWithoutMetadata {
    <# Skill folders with a SKILL.md but no sidecar, excluding Git-ignored private skills and Spec Kit-generated speckit-* skills. #>
    param([Parameter(Mandatory)][string]$RepoRoot)
    $Skills = @(Get-ChildItem -Path (Join-Path $RepoRoot '.github/skills/*/SKILL.md') -File |
        Where-Object { $_.Directory.Name -notlike $script:SpecKitSkillPattern -and -not (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'skill.metadata.yaml')) })
    if (-not $Skills.Count) { return @() }
    return @($Skills | Where-Object { -not (Test-SkillIgnoredPath -RepoRoot $RepoRoot -Path $_.FullName) } |
        ForEach-Object { $_.Directory.Name } | Sort-Object)
}

function Test-SkillComponent {
    <# Returns validation errors; an empty result means the catalog of components is consistent. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object[]]$Component)
    $Errors = [Collections.Generic.List[string]]::new()
    foreach ($Missing in Get-SkillWithoutMetadata -RepoRoot $RepoRoot) {
        $Errors.Add("${Missing}: missing skill.metadata.yaml; run New-SkillMetadata.ps1 -Id $Missing.")
    }
    $Ids = @{}
    foreach ($Item in $Component) { $Ids[$Item.Id] = $Item }
    $Schema = [IO.File]::ReadAllText($script:SchemaPath)
    foreach ($Item in $Component) {
        if ($Item.Kind -eq 'skill') {
            $Json = $Item.Metadata | ConvertTo-Json -Depth 20
            $SchemaErrors = $null
            if (-not (Test-Json -Json $Json -Schema $Schema -ErrorVariable SchemaErrors -ErrorAction SilentlyContinue)) {
                $Errors.Add("$($Item.Id): sidecar does not match the schema: $($SchemaErrors -join '; ')")
                continue
            }
            if (-not $Item.Description) { $Errors.Add("$($Item.Id): SKILL.md has no description.") }
            $Markdown = [IO.File]::ReadAllText((Join-Path $RepoRoot "$($Item.Path)/SKILL.md"))
            foreach ($PortableError in Test-SkillPortableFrontmatter -Id $Item.Id -Markdown $Markdown) { $Errors.Add($PortableError) }
            $Declared = @(@($Item.Required) + @($Item.Related) | ForEach-Object { $_.id })
            $Reported = @{}
            foreach ($Link in Get-SkillLink -RepoRoot $RepoRoot -Id $Item.Id) {
                $Message = if ($Link.Skill) {
                    if ($Link.Skill -notin $Declared) { "$($Item.Id): $($Link.Source) links to skill '$($Link.Skill)'; add it to required or related." }
                }
                elseif ($Link.File -notin $Item.ExternalFiles) { "$($Item.Id): $($Link.Source) links to '$($Link.File)'; add it to externalFiles." }
                if ($Message -and -not $Reported.ContainsKey($Message)) { $Reported[$Message] = $true; $Errors.Add($Message) }
            }
        }
        elseif ($Item.Version -cnotmatch $script:VersionPattern) { $Errors.Add("$($Item.Id): invalid version '$($Item.Version)'.") }
        $Seen = @{}
        foreach ($Edge in @($Item.Required) + @($Item.Related)) {
            if ($Edge.id -ceq $Item.Id) { $Errors.Add("$($Item.Id): references itself.") }
            elseif (-not $Ids.ContainsKey($Edge.id) -or $Ids[$Edge.id].Kind -ne 'skill') { $Errors.Add("$($Item.Id): unknown skill '$($Edge.id)'.") }
            if ($Seen.ContainsKey($Edge.id)) { $Errors.Add("$($Item.Id): '$($Edge.id)' is listed more than once.") }
            $Seen[$Edge.id] = $true
        }
        foreach ($File in $Item.ExternalFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $File) -PathType Leaf)) { $Errors.Add("$($Item.Id): external file '$File' does not exist.") }
            elseif ($File.StartsWith("$($Item.Path)/", [StringComparison]::Ordinal)) { $Errors.Add("$($Item.Id): '$File' is already inside the skill folder.") }
        }
    }
    $State = @{}
    function Visit([string]$Id, [string[]]$Trail) {
        if ($State[$Id] -eq 'done' -or -not $Ids.ContainsKey($Id)) { return }
        if ($State[$Id] -eq 'visiting') { $Errors.Add("Required cycle: $(($Trail + $Id) -join ' -> ')."); return }
        $State[$Id] = 'visiting'
        foreach ($Edge in $Ids[$Id].Required) { Visit $Edge.id ($Trail + $Id) }
        $State[$Id] = 'done'
    }
    foreach ($Item in $Component) { Visit $Item.Id @() }
    foreach ($CatalogueError in Test-SkillCatalogue -RepoRoot $RepoRoot -Component $Component) { $Errors.Add($CatalogueError) }
    return @($Errors)
}

function Get-SkillLink {
    <# Relative Markdown links from a skill's documents to other skills or to repository files outside the skill folder. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Id)
    $Root = [IO.Path]::GetFullPath($RepoRoot)
    $Folder = Join-Path $Root ".github/skills/$Id"
    foreach ($Document in Get-ChildItem -LiteralPath $Folder -Filter '*.md' -Recurse -File | Sort-Object FullName) {
        # Links inside fenced code blocks are examples, not dependencies.
        $Text = [regex]::Replace([IO.File]::ReadAllText($Document.FullName), '(?ms)^(`{3,}|~{3,})[^\n]*\n.*?^\1\s*$', '')
        $Source = [IO.Path]::GetRelativePath($Folder, $Document.FullName).Replace('\', '/')
        foreach ($Match in [regex]::Matches($Text, '\]\(([^)\s#]+)')) {
            $Link = $Match.Groups[1].Value
            if ($Link -match '^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|/)') { continue }
            $Target = [IO.Path]::GetFullPath((Join-Path $Document.DirectoryName ([uri]::UnescapeDataString($Link))))
            $Relative = [IO.Path]::GetRelativePath($Root, $Target).Replace('\', '/')
            if ($Relative -eq ".github/skills/$Id" -or $Relative.StartsWith(".github/skills/$Id/") -or $Relative.StartsWith('..')) { continue }
            if ($Relative -match '^\.github/skills/([^/]+)') { [pscustomobject]@{ Source = $Source; Skill = $Matches[1]; File = $null } }
            elseif (Test-Path -LiteralPath $Target -PathType Leaf) { [pscustomobject]@{ Source = $Source; Skill = $null; File = $Relative } }
        }
    }
}

function Get-SkillCatalogueVersion {
    <# Maps each skill linked from the catalogue page to the backtick-quoted versions on its rows; $null when there is no page. #>
    param([Parameter(Mandatory)][string]$RepoRoot)
    $Path = Join-Path $RepoRoot $script:CataloguePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $Rows = @{}
    foreach ($Line in [IO.File]::ReadAllLines($Path)) {
        $Link = [regex]::Match($Line, '\]\(\.\./\.github/skills/([a-z0-9-]+)/SKILL\.md\)')
        if (-not $Link.Success) { continue }
        $Version = [regex]::Match($Line, '`(\d+\.\d+\.\d+)`')
        $Id = $Link.Groups[1].Value
        if (-not $Rows.ContainsKey($Id)) { $Rows[$Id] = [Collections.Generic.List[string]]::new() }
        $Rows[$Id].Add($(if ($Version.Success) { $Version.Groups[1].Value } else { '' }))
    }
    return $Rows
}

function Test-SkillCatalogue {
    <# Returns errors unless the catalogue page lists every skill exactly once at its current version. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object[]]$Component)
    $Rows = Get-SkillCatalogueVersion -RepoRoot $RepoRoot
    if ($null -eq $Rows) { return @() }
    $Skills = @($Component | Where-Object Kind -eq 'skill')
    $Errors = foreach ($Item in $Skills) {
        if (-not $Rows.ContainsKey($Item.Id)) { "$($Item.Id): missing from $($script:CataloguePath); add a row with version ``$($Item.Version)``."; continue }
        $Versions = $Rows[$Item.Id]
        if ($Versions.Count -gt 1) { "$($Item.Id): listed $($Versions.Count) times in $($script:CataloguePath)." }
        elseif ($Versions[0] -cne $Item.Version) {
            "$($Item.Id): $($script:CataloguePath) shows '$($Versions[0])' but the version is $($Item.Version); run Set-SkillVersion.ps1 or fix the row."
        }
    }
    foreach ($Id in $Rows.Keys | Where-Object { $_ -notin $Skills.Id } | Sort-Object) { $Errors = @($Errors) + "${Id}: listed in $($script:CataloguePath) but is not a published skill." }
    return @($Errors)
}

function Set-SkillCatalogueVersion {
    <# Rewrites the version cell on the catalogue row for one skill; no-op when there is no page or row. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Version)
    $Path = Join-Path $RepoRoot $script:CataloguePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $Text = [IO.File]::ReadAllText($Path)
    $Row = '(?m)^(.*\]\(\.\./\.github/skills/' + [regex]::Escape($Id) + '/SKILL\.md\).*?)`\d+\.\d+\.\d+`'
    $Updated = [regex]::Replace($Text, $Row, { param($Match) "$($Match.Groups[1].Value)``$Version``" })
    if ($Updated -cne $Text) { [IO.File]::WriteAllText($Path, $Updated) }
}

function Get-SkillReleasedVersion {
    <# Highest published <id>/X.Y.Z tag version, or $null when unreleased. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Id)
    $Versions = Invoke-SkillTool git @('tag', '--list', "$Id/*") -WorkingDirectory $RepoRoot |
        ForEach-Object { $_.Substring($Id.Length + 1) } | Where-Object { $_ -cmatch $script:VersionPattern } |
        ForEach-Object { [version]$_ } | Sort-Object -Descending
    if (@($Versions).Count -eq 0) { return $null }
    return @($Versions)[0]
}

function Get-SkillVersionPath {
    param([Parameter(Mandatory)][object]$Component)
    return @($Component.Path) + @($Component.ExternalFiles)
}

function Test-SkillChanged {
    <# True when the component's files differ from the given release tag, including uncommitted edits. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object]$Component, [Parameter(Mandatory)][version]$Released)
    Push-Location -LiteralPath $RepoRoot
    try { & git diff --quiet "$($Component.Id)/$Released" -- @(Get-SkillVersionPath $Component); return $LASTEXITCODE -ne 0 }
    finally { Pop-Location }
}

function Set-SkillMetadataValue {
    <# Edits one scalar in place with yq, preserving comments and layout. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object]$Component, [Parameter(Mandatory)][string]$Version, [string]$DependencyId)
    $Path = Join-Path $RepoRoot $Component.ManifestPath
    $Expression = if ($DependencyId) { '(.required[] | select(.id == strenv(SKILL_DEPENDENCY))).version = strenv(SKILL_VERSION)' }
    elseif ($Component.Kind -eq 'bootstrap') { '.extension.version = strenv(SKILL_VERSION)' }
    else { '.version = strenv(SKILL_VERSION)' }
    $env:SKILL_VERSION = $Version
    $env:SKILL_DEPENDENCY = $DependencyId
    try { & yq -i $Expression $Path; if ($LASTEXITCODE -ne 0) { throw "Could not update $Path." } }
    finally { Remove-Item Env:SKILL_VERSION, Env:SKILL_DEPENDENCY -ErrorAction SilentlyContinue }
}

function Test-SkillVersion {
    <# Returns errors for skills changed since their last release without a bump, and for stale required pins. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object[]]$Component)
    $Errors = [Collections.Generic.List[string]]::new()
    $Ids = @{}
    foreach ($Item in $Component) { $Ids[$Item.Id] = $Item }
    foreach ($Item in $Component) {
        $Released = Get-SkillReleasedVersion -RepoRoot $RepoRoot -Id $Item.Id
        if ($null -ne $Released) {
            $Current = ConvertTo-SkillVersion $Item.Version
            $Next = @(
                [version]::new($Released.Major, $Released.Minor, $Released.Build + 1)
                [version]::new($Released.Major, $Released.Minor + 1, 0)
                [version]::new($Released.Major + 1, 0, 0))
            if ($Current -lt $Released) { $Errors.Add("$($Item.Id): version $Current is lower than released $Released.") }
            elseif ($Current -ne $Released -and $Next -notcontains $Current) {
                $Errors.Add("$($Item.Id): version $Current skips past one bump from released $Released; use one of $($Next -join ', ') via Set-SkillVersion.ps1 -Id $($Item.Id).")
            }
            elseif ($Current -eq $Released -and (Test-SkillChanged -RepoRoot $RepoRoot -Component $Item -Released $Released)) {
                $Errors.Add("$($Item.Id): changed since $($Item.Id)/$Released; run Set-SkillVersion.ps1 -Id $($Item.Id).")
            }
        }
        foreach ($Edge in $Item.Required) {
            if ($Ids.ContainsKey($Edge.id) -and $Edge.version -cne $Ids[$Edge.id].Version) {
                $Errors.Add("$($Item.Id): requires $($Edge.id) $($Edge.version) but its version is $($Ids[$Edge.id].Version); run Set-SkillVersion.ps1.")
            }
        }
    }
    return @($Errors)
}

function Get-SkillPackageFile {
    <# Committed files packaged for one component, as repository-relative paths with Git modes. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object]$Component)
    $Paths = @($Component.Path) + @($Component.ExternalFiles)
    if ($Component.Kind -eq 'skill') { $Paths += 'LICENSE' }
    $Dirty = Invoke-SkillTool git (@('status', '--porcelain', '--') + $Paths) -WorkingDirectory $RepoRoot
    if ($Dirty) { throw "$($Component.Id): commit or stash changes before building: $($Dirty -join ', ')" }
    $Files = [ordered]@{}
    foreach ($Line in Invoke-SkillTool git (@('ls-files', '--stage', '--') + $Paths) -WorkingDirectory $RepoRoot) {
        $Parts = $Line -split '\s+', 4
        if ($Parts[0] -notin @('100644', '100755')) { throw "$($Component.Id): unsupported file type for '$($Parts[3])'." }
        $Files[$Parts[3]] = $Parts[0]
    }
    return $Files
}

function ConvertTo-SkillYamlText {
    param([Parameter(Mandatory)][object]$Value)
    $Yaml = ($Value | ConvertTo-Json -Depth 20) | & yq -p=json -o=yaml -P '.'
    if ($LASTEXITCODE -ne 0) { throw 'YAML conversion failed.' }
    return ($Yaml -join "`n") + "`n"
}

function New-SkillExtensionManifest {
    param([Parameter(Mandatory)][object]$Component)
    $Description = $Component.Description
    [ordered]@{
        schema_version = '1.0'
        extension      = [ordered]@{ id = $Component.Id; name = $Component.Id; version = $Component.Version; description = $Description }
        requires       = [ordered]@{ speckit_version = '>=1.2.3' }
        provides       = [ordered]@{ templates = @([ordered]@{ name = $Component.Id; file = "resources/$($Component.Path)/SKILL.md"; description = $Description }) }
    }
}

function Write-SkillZip {
    <# Writes entries in ordinal order with fixed timestamps so equal inputs produce equal bytes. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][Collections.IDictionary]$Entry)
    $Names = [string[]]@($Entry.Keys)
    [Array]::Sort($Names, [StringComparer]::Ordinal)
    $Stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
    try {
        $Zip = [IO.Compression.ZipArchive]::new($Stream, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($Name in $Names) {
                $Item = $Entry[$Name]
                $ZipEntry = $Zip.CreateEntry($Name, [IO.Compression.CompressionLevel]::Optimal)
                $ZipEntry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $ZipEntry.ExternalAttributes = [Convert]::ToInt32($Item.Mode, 8) -shl 16
                $Writer = $ZipEntry.Open()
                try { $Writer.Write($Item.Bytes, 0, $Item.Bytes.Length) }
                finally { $Writer.Dispose() }
            }
        }
        finally { $Zip.Dispose() }
    }
    finally { $Stream.Dispose() }
}

function New-SkillExtensionArchive {
    <# Builds <id>-<version>.zip for one component and returns its path and SHA-256. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object]$Component, [Parameter(Mandatory)][string]$OutputDirectory)
    $Files = Get-SkillPackageFile -RepoRoot $RepoRoot -Component $Component
    $Entry = [ordered]@{}
    foreach ($File in $Files.Keys) {
        $Bytes = [IO.File]::ReadAllBytes((Join-Path $RepoRoot $File))
        $Name = if ($Component.Kind -eq 'bootstrap') { $File.Substring($Component.Path.Length + 1) } else { "resources/$File" }
        $Entry[$Name] = @{ Bytes = $Bytes; Mode = $Files[$File] }
    }
    if ($Component.Kind -eq 'skill') {
        if (-not $Files.Contains("$($Component.Path)/SKILL.md")) { throw "$($Component.Id): SKILL.md is not committed." }
        $Manifest = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-SkillYamlText (New-SkillExtensionManifest $Component)))
        $Entry['extension.yml'] = @{ Bytes = $Manifest; Mode = '100644' }
    }
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $Path = Join-Path $OutputDirectory "$($Component.Id)-$($Component.Version).zip"
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path }
    Write-SkillZip -Path $Path -Entry $Entry
    [pscustomobject]@{ Id = $Component.Id; Version = $Component.Version; Path = $Path; Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function New-SkillPluginManifest {
    <# Agent Plugins plugin.json for one skill; required and related skills live under the skill-library extension namespace. #>
    param([Parameter(Mandatory)][object]$Component, [string]$Repository)
    $Manifest = [ordered]@{ '$schema' = $script:PluginSchema; name = $Component.Id; version = $Component.Version; description = $Component.Description }
    if ($Repository) { $Manifest.repository = "https://github.com/$Repository" }
    if ($Component.Facets.Count) { $Manifest.keywords = @($Component.Facets) }
    $Manifest.extensions = [ordered]@{
        $script:PluginNamespace = [ordered]@{
            required = @($Component.Required | ForEach-Object { [ordered]@{ id = $_.id; version = $_.version } })
            related  = @($Component.Related | ForEach-Object { [ordered]@{ id = $_.id; reason = $_.reason } })
        }
    }
    return $Manifest
}

function New-SkillPluginArchive {
    <# Builds <id>-<version>-plugin.zip: an Agent Plugin with the skill under skills/<id>/ and external files at their .github-relative paths. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object]$Component, [Parameter(Mandatory)][string]$OutputDirectory, [string]$Repository)
    if ($Component.Kind -ne 'skill') { throw "$($Component.Id): only skills are packaged as Agent Plugins." }
    $Files = Get-SkillPackageFile -RepoRoot $RepoRoot -Component $Component
    $SkillRoot = "skills/$($Component.Id)"
    $Utf8 = [Text.UTF8Encoding]::new($false)
    $Entry = [ordered]@{}
    foreach ($File in $Files.Keys) {
        $Bytes = [IO.File]::ReadAllBytes((Join-Path $RepoRoot $File))
        # Stripping .github/ keeps SKILL.md links such as ../../instructions/x.md resolving inside the plugin root.
        $Name = if ($File.StartsWith("$($Component.Path)/", [StringComparison]::Ordinal)) { "$SkillRoot/$($File.Substring($Component.Path.Length + 1))" }
        elseif ($File.StartsWith('.github/', [StringComparison]::Ordinal)) { $File.Substring('.github/'.Length) }
        elseif ($File -ceq 'LICENSE') { $File }
        else { throw "$($Component.Id): external file '$File' must be under .github/ to resolve inside an Agent Plugin." }
        if ($Name -ceq "$SkillRoot/SKILL.md") { $Bytes = $Utf8.GetBytes((ConvertTo-SkillPortableMarkdown $Utf8.GetString($Bytes))) }
        $Entry[$Name] = @{ Bytes = $Bytes; Mode = $Files[$File] }
    }
    if (-not $Entry.Contains("$SkillRoot/SKILL.md")) { throw "$($Component.Id): SKILL.md is not committed." }
    $Manifest = (New-SkillPluginManifest -Component $Component -Repository $Repository | ConvertTo-Json -Depth 20) + "`n"
    $Entry['plugin.json'] = @{ Bytes = $Utf8.GetBytes($Manifest); Mode = '100644' }
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $Path = Join-Path $OutputDirectory "$($Component.Id)-$($Component.Version)-plugin.zip"
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path }
    Write-SkillZip -Path $Path -Entry $Entry
    [pscustomobject]@{ Id = $Component.Id; Version = $Component.Version; Path = $Path; Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function New-SkillCatalog {
    <# Builds a Spec Kit catalog from published releases; the highest version of each ID is current. #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Release)
    $Extensions = [ordered]@{}
    foreach ($Group in $Release | Group-Object Id | Sort-Object Name) {
        $Ordered = @($Group.Group | Sort-Object { ConvertTo-SkillVersion $_.Version } -Descending)
        $Records = @(foreach ($Item in $Ordered) {
            $Library = [ordered]@{
                required = @($Item.Required | ForEach-Object { [ordered]@{ id = $_.id; version = $_.version } })
                related  = @($Item.Related | ForEach-Object { [ordered]@{ id = $_.id; reason = $_.reason } })
            }
            if ($Item.PSObject.Properties['PluginUrl'] -and $Item.PluginUrl) {
                $Library.agent_plugin = [ordered]@{ download_url = $Item.PluginUrl; sha256 = $Item.PluginSha256 }
            }
            [ordered]@{
                download_url  = $Item.Url
                sha256        = $Item.Sha256
                requires      = [ordered]@{ speckit_version = '>=1.2.3' }
                skill_library = $Library
            }
        })
        $Current = $Ordered[0]
        $Entry = [ordered]@{ name = $Current.Id; description = $Current.Description; version = $Current.Version; tags = @($Current.Facets) }
        foreach ($Key in $Records[0].Keys) { $Entry[$Key] = $Records[0][$Key] }
        if ($Ordered.Count -gt 1) {
            $Entry.releases = [ordered]@{}
            for ($Index = 1; $Index -lt $Ordered.Count; $Index++) { $Entry.releases[$Ordered[$Index].Version] = $Records[$Index] }
        }
        $Extensions[$Group.Name] = $Entry
    }
    [ordered]@{ schema_version = '1.0'; extensions = $Extensions }
}

function New-SkillCatalogPage {
    <# Renders a static HTML index of the catalog's current versions for GitHub Pages. #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Catalog)
    $Encode = { param([object]$Value) [Net.WebUtility]::HtmlEncode([string]$Value) }
    $Rows = foreach ($Pair in $Catalog.extensions.GetEnumerator()) {
        $Entry = $Pair.Value
        $Required = @($Entry.skill_library.required | ForEach-Object { "$($_.id) $($_.version)" }) -join ', '
        $Plugin = if ($Entry.skill_library.Contains('agent_plugin')) { "<a href=`"$(& $Encode $Entry.skill_library.agent_plugin.download_url)`">plugin</a>" } else { '' }
        "<tr><td><code>$(& $Encode $Pair.Key)</code></td><td><a href=`"$(& $Encode $Entry.download_url)`">$(& $Encode $Entry.version)</a></td>" +
        "<td>$Plugin</td><td>$(& $Encode $Entry.description)</td><td>$(& $Encode $Required)</td></tr>"
    }
    @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Skill library catalog</title>
<style>
body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 70rem; padding: 0 1rem; color: #1f2328; }
table { border-collapse: collapse; width: 100%; }
th, td { border-bottom: 1px solid #d0d7de; padding: .5rem; text-align: left; vertical-align: top; }
th { background: #f6f8fa; }
</style>
</head>
<body>
<h1>Skill library catalog</h1>
<p>Each skill is a Spec Kit extension. Point Spec Kit at <a href="catalog.json">catalog.json</a> and install with <code>/speckit-skill-library install &lt;skill&gt;</code>.
Skills released with an <a href="https://agent-plugins.org/">Agent Plugins</a> package also link it, for any conformant client.</p>
<table>
<thead><tr><th>Skill</th><th>Version</th><th>Agent Plugin</th><th>Description</th><th>Requires</th></tr></thead>
<tbody>
$($Rows -join "`n")
</tbody>
</table>
</body>
</html>
"@
}

Export-ModuleMember -Function Invoke-SkillTool, Read-SkillYaml, ConvertFrom-SkillYaml, Get-SkillFrontmatter, ConvertTo-SkillVersion, Get-SkillComponent,
    Get-SkillWithoutMetadata, Test-SkillComponent, Get-SkillLink, Get-SkillCatalogueVersion, Test-SkillCatalogue, Set-SkillCatalogueVersion,
    Get-SkillReleasedVersion, Test-SkillChanged, Set-SkillMetadataValue, Test-SkillVersion, Get-SkillPackageFile,
    New-SkillExtensionManifest, New-SkillExtensionArchive, ConvertTo-SkillPortableMarkdown, Test-SkillPortableFrontmatter, New-SkillPluginManifest,
    New-SkillPluginArchive, New-SkillCatalog, New-SkillCatalogPage
