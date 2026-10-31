#Requires -Version 7.4
Set-StrictMode -Version 3.0

$env:GIT_AUTHOR_NAME = $env:GIT_COMMITTER_NAME = 'Test'
$env:GIT_AUTHOR_EMAIL = $env:GIT_COMMITTER_EMAIL = 'test@example.com'

function Invoke-FixtureGit {
    # Plain $args so git switches such as -A are never bound as PowerShell parameters.
    $Repo = $args[0]
    $GitArgument = [string[]]@($args | Select-Object -Skip 1)
    Push-Location -LiteralPath $Repo
    try { $Output = & git @GitArgument 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $GitArgument failed: $Output" } }
    finally { Pop-Location }
}

function Write-FixtureText {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $Full = Join-Path $Repo $Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Full))
    [IO.File]::WriteAllText($Full, $Text)
}

function Write-FixtureSkill {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Id, [string]$Metadata, [string]$Body = '')
    Write-FixtureText $Repo ".github/skills/$Id/SKILL.md" "---`nname: $Id`ndescription: Guidance for $Id.`n---`n`n# $Id`n$Body"
    if ($Metadata) { Write-FixtureText $Repo ".github/skills/$Id/skill.metadata.yaml" $Metadata }
}

function New-SkillFixture {
    <# Creates a committed repository: alpha requires beta, offers gamma and uses one external instruction file. #>
    param([Parameter(Mandatory)][string]$Root)
    $Repo = Join-Path $Root ([guid]::NewGuid())
    [void][IO.Directory]::CreateDirectory($Repo)
    Invoke-FixtureGit $Repo init -q -b main
    Write-FixtureText $Repo 'LICENSE' "MIT`n"
    Write-FixtureText $Repo '.github/instructions/x.instructions.md' "# X`n"
    Write-FixtureSkill $Repo 'alpha' "version: 1.0.0`nfacets: [architecture]`nrequired:`n  - id: beta`n    version: 1.0.0`nrelated:`n  - id: gamma`n    reason: Optional extra.`nexternalFiles:`n  - .github/instructions/x.instructions.md`n"
    Write-FixtureSkill $Repo 'beta' "version: 1.0.0`n"
    Write-FixtureSkill $Repo 'gamma' "version: 1.0.0`n"
    Invoke-FixtureGit $Repo add -A
    Invoke-FixtureGit $Repo commit -q -m init
    return $Repo
}

function New-FakeCommand {
    <# Puts an executable PowerShell script named $Name first on PATH for the current process. #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Script)
    $Bin = Join-Path $Root 'bin'
    [void][IO.Directory]::CreateDirectory($Bin)
    $Path = Join-Path $Bin $Name
    [IO.File]::WriteAllText($Path, "#!/usr/bin/env pwsh`n$Script`n")
    & chmod +x $Path
    if (-not $env:PATH.StartsWith("$Bin$([IO.Path]::PathSeparator)")) { $env:PATH = "$Bin$([IO.Path]::PathSeparator)$env:PATH" }
}

Export-ModuleMember -Function Invoke-FixtureGit, Write-FixtureText, Write-FixtureSkill, New-SkillFixture, New-FakeCommand
