#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../../skill-library/scripts/SkillLibrary.psm1') -Force
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
    $Manifest = Read-SkillYaml (Join-Path $RepoRoot '.github/skills/skill-library-vendoring/framework.yaml')
    $Tracked = @(git -C $RepoRoot ls-files --cached --others --exclude-standard)
    function Get-ManagedFile {
        foreach ($Entry in $Manifest.managed) {
            $Prefix = $Entry.path
            $Excluded = @($Entry['exclude'] ?? @())
            $Tracked | Where-Object { ($_ -ceq $Prefix -or $_.StartsWith($Prefix, [StringComparison]::Ordinal)) -and $_ -cnotin $Excluded }
        }
    }
}

Describe 'framework.yaml' -Tag 'Unit' {
    It 'lists only tracked paths' {
        foreach ($Entry in $Manifest.managed) { @(Get-ManagedFile | Where-Object { $_.StartsWith($Entry.path, [StringComparison]::Ordinal) }) | Should -Not -BeNullOrEmpty -Because "$($Entry.path) must exist" }
        foreach ($Entry in $Manifest.seeded) { $Tracked | Should -Contain $Entry.from -Because "$($Entry.path) is seeded from it" }
    }

    It 'covers the skill-library tooling and the bootstrap extension' {
        $Paths = @($Manifest.managed | ForEach-Object path)
        $Paths | Should -Contain '.github/skills/skill-library/'
        $Paths | Should -Contain 'src/skill-library-extension/'
        @($Manifest.seeded | ForEach-Object path) | Should -Contain '.github/skill-library.config.yaml'
    }

    It 'keeps this repository''s configured values out of managed files' {
        $Config = Get-SkillLibraryConfig -RepoRoot $RepoRoot
        $CatalogHost = ([uri]$Config.CatalogUrl).Host
        $Leaks = foreach ($File in Get-ManagedFile) {
            $Text = [IO.File]::ReadAllText((Join-Path $RepoRoot $File))
            foreach ($Value in $CatalogHost, $Config.PluginNamespace) { if ($Text.Contains($Value, [StringComparison]::OrdinalIgnoreCase)) { "${File}: $Value" } }
        }
        @($Leaks) | Should -BeNullOrEmpty
    }

    It 'seeds a configuration template that the tooling rejects until it is filled in' {
        $Repo = Join-Path $TestDrive 'seeded'
        [void][IO.Directory]::CreateDirectory((Join-Path $Repo '.github'))
        Copy-Item (Join-Path $RepoRoot '.github/skills/skill-library-vendoring/assets/skill-library.config.yaml') (Join-Path $Repo '.github/skill-library.config.yaml')
        { Get-SkillLibraryConfig -RepoRoot $Repo } | Should -Throw '*still holds template example values*'
    }
}
