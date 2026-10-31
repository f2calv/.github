#Requires -Version 7.4
Set-StrictMode -Version 3.0

$script:BootstrapId = 'skill'
$script:BootstrapPath = 'src/skill-library-extension'
$script:SchemaPath = Join-Path $PSScriptRoot '../skill-metadata.schema.json'
$script:VersionPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

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

function Get-SkillComponent {
    <# Returns every skill with a sidecar plus the bootstrap extension. #>
    param([Parameter(Mandatory)][string]$RepoRoot)
    $Components = foreach ($Sidecar in Get-ChildItem -Path (Join-Path $RepoRoot '.github/skills/*/skill.metadata.yaml') -File | Sort-Object FullName) {
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

function Test-SkillComponent {
    <# Returns validation errors; an empty result means the catalog of components is consistent. #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][object[]]$Component)
    $Errors = [Collections.Generic.List[string]]::new()
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
    return @($Errors)
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
            if ($Current -lt $Released) { $Errors.Add("$($Item.Id): version $Current is lower than released $Released.") }
            elseif ($Current -eq $Released) {
                Push-Location -LiteralPath $RepoRoot
                try { & git diff --quiet "$($Item.Id)/$Released" -- @(Get-SkillVersionPath $Item); $Changed = $LASTEXITCODE -ne 0 }
                finally { Pop-Location }
                if ($Changed) { $Errors.Add("$($Item.Id): changed since $($Item.Id)/$Released; run Set-SkillVersion.ps1 -Id $($Item.Id).") }
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

function New-SkillCatalog {
    <# Builds a Spec Kit catalog from published releases; the highest version of each ID is current. #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Release)
    $Extensions = [ordered]@{}
    foreach ($Group in $Release | Group-Object Id | Sort-Object Name) {
        $Ordered = @($Group.Group | Sort-Object { ConvertTo-SkillVersion $_.Version } -Descending)
        $Records = foreach ($Item in $Ordered) {
            [ordered]@{
                download_url  = $Item.Url
                sha256        = $Item.Sha256
                requires      = [ordered]@{ speckit_version = '>=1.2.3' }
                skill_library = [ordered]@{
                    required = @($Item.Required | ForEach-Object { [ordered]@{ id = $_.id; version = $_.version } })
                    related  = @($Item.Related | ForEach-Object { [ordered]@{ id = $_.id; reason = $_.reason } })
                }
            }
        }
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

Export-ModuleMember -Function Invoke-SkillTool, Read-SkillYaml, ConvertFrom-SkillYaml, Get-SkillFrontmatter, ConvertTo-SkillVersion, Get-SkillComponent,
    Test-SkillComponent, Get-SkillReleasedVersion, Test-SkillVersion, Get-SkillPackageFile, New-SkillExtensionManifest, New-SkillExtensionArchive, New-SkillCatalog
