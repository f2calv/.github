#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SkillLibraryFixture.psm1') -Force
    $Script = Join-Path $PSScriptRoot '../Publish-SkillRelease.ps1'
    $SavedPath = $env:PATH
    # Stores releases as folders, tags the target commit like GitHub does, and logs every call.
    New-FakeCommand -Root $TestDrive -Name 'gh' -Script @'
$A = [string[]]$args
$State = $env:FAKE_GH_STATE
Add-Content -LiteralPath (Join-Path $State 'calls.log') -Value ($A -join ' ')
$Releases = Join-Path $State 'releases'
[void](New-Item -ItemType Directory -Force -Path $Releases)
$Dir = if ($A.Count -gt 2) { Join-Path $Releases ($A[2] -replace '/', '__') } else { '' }
switch ($A[1]) {
    'create' {
        [void](New-Item -ItemType Directory -Force -Path $Dir)
        Copy-Item -LiteralPath $A[3] -Destination $Dir
        & git tag $A[2] $A[[array]::IndexOf($A, '--target') + 1]
        if ($LASTEXITCODE -ne 0) { exit 1 }
    }
    'upload' { Copy-Item -LiteralPath $A[3] -Destination $Dir -Force }
    'list' { Get-ChildItem -LiteralPath $Releases -Directory | ForEach-Object { $_.Name -replace '__', '/' } }
    'download' {
        $Target = $A[[array]::IndexOf($A, '--dir') + 1]
        [void](New-Item -ItemType Directory -Force -Path $Target)
        Copy-Item -Path (Join-Path $Dir '*.zip') -Destination $Target
    }
    'view' {
        if (-not (Test-Path -LiteralPath $Dir)) { exit 1 }
        if ($A -contains '--json') { "https://example.com/download/$($A[2])/$((Get-ChildItem -LiteralPath $Dir -Filter '*.zip')[0].Name)" }
    }
}
exit 0
'@
}

AfterAll { $env:PATH = $SavedPath; Remove-Item Env:FAKE_GH_STATE -ErrorAction SilentlyContinue }

Describe 'Publish-SkillRelease' -Tag 'Unit' {
    BeforeEach {
        $Repo = New-SkillFixture $TestDrive
        $env:FAKE_GH_STATE = Join-Path $TestDrive ([guid]::NewGuid())
        [void][IO.Directory]::CreateDirectory($env:FAKE_GH_STATE)
        function Get-Calls { @(Get-Content -LiteralPath (Join-Path $env:FAKE_GH_STATE 'calls.log') -ErrorAction SilentlyContinue) }
        function Get-Catalog { Get-Content -Raw (Join-Path $env:FAKE_GH_STATE 'releases/skills-catalog/catalog.json') | ConvertFrom-Json -AsHashtable }
        function Invoke-Publish([switch]$DryRun) { & $Script -RepoRoot $Repo -Repository 'owner/example' -OutputDirectory (Join-Path $TestDrive ([guid]::NewGuid())) -DryRun:$DryRun 6> $null }
    }

    It 'reports pending releases without calling GitHub in a dry run' {
        Invoke-Publish -DryRun
        Get-Calls | Should -BeNullOrEmpty
    }

    It 'publishes every unreleased skill and creates the catalog release' {
        Invoke-Publish
        $Calls = Get-Calls
        @($Calls | Where-Object { $_ -like 'release create alpha/1.0.0 *--latest=false' }).Count | Should -Be 1
        @($Calls | Where-Object { $_ -like 'release create skills-catalog *' }).Count | Should -Be 1
        $Catalog = Get-Catalog
        $Catalog.extensions.Keys | Sort-Object | Should -Be @('alpha', 'beta', 'gamma')
        $Catalog.extensions['alpha'].download_url | Should -Be 'https://example.com/download/alpha/1.0.0/alpha-1.0.0.zip'
        $Catalog.extensions['alpha'].skill_library.required[0].id | Should -Be 'beta'
    }

    It 'publishes only bumped skills next time and keeps earlier versions in the catalog' {
        Invoke-Publish
        Write-FixtureText $Repo '.github/skills/beta/SKILL.md' "---`nname: beta`ndescription: Changed.`n---`n"
        & (Join-Path $PSScriptRoot '../Set-SkillVersion.ps1') -RepoRoot $Repo -Bump minor 6> $null
        Invoke-FixtureGit $Repo commit -q -am bump
        Invoke-Publish
        $Created = @(Get-Calls | Where-Object { $_ -like 'release create *' } | ForEach-Object { ($_ -split ' ')[2] })
        $Created | Should -Be @('alpha/1.0.0', 'beta/1.0.0', 'gamma/1.0.0', 'skills-catalog', 'alpha/1.0.1', 'beta/1.1.0')
        @(Get-Calls | Where-Object { $_ -like 'release upload skills-catalog *--clobber' }).Count | Should -Be 1
        $Catalog = Get-Catalog
        $Catalog.extensions['beta'].version | Should -Be '1.1.0'
        $Catalog.extensions['alpha'].skill_library.required[0].version | Should -Be '1.1.0'
        $Catalog.extensions['alpha'].releases['1.0.0'].skill_library.required[0].version | Should -Be '1.0.0'
    }

    It 'refuses to publish when a changed skill was not bumped' {
        Invoke-FixtureGit $Repo tag 'gamma/1.0.0'
        Write-FixtureText $Repo '.github/skills/gamma/SKILL.md' "---`nname: gamma`ndescription: Changed.`n---`n"
        Invoke-FixtureGit $Repo commit -q -am change
        { Invoke-Publish } | Should -Throw '*gamma: changed since gamma/1.0.0*'
        Get-Calls | Should -BeNullOrEmpty
    }
}
