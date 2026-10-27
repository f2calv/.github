#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Invoke-Validation.ps1')
    $script:Python = if ($env:SKILL_LIBRARY_TEST_PYTHON) { $env:SKILL_LIBRARY_TEST_PYTHON } else { 'python3' }
    $script:Validator = Join-Path $PSScriptRoot '../Invoke-Validation.ps1'
    $script:Schema = Join-Path $PSScriptRoot '../../skill-metadata.schema.json'

    function New-MetadataFixture {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path (Join-Path $Root '.github/skills') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $Root '.config') -Force)
        Set-Content -LiteralPath (Join-Path $Root 'LICENSE') -Value 'Synthetic license notice.'
        Set-Content -LiteralPath (Join-Path $Root '.config/skill-library.yaml') -Value "license: MIT`nnotices: [LICENSE]"
        return $Root
    }

    function Set-FixtureSkill {
        param([string]$Root, [string]$Name = 'example-skill', [hashtable]$Changes = @{})
        $Directory = Join-Path $Root ".github/skills/$Name"
        [void](New-Item -ItemType Directory -Path $Directory -Force)
        Set-Content -LiteralPath (Join-Path $Directory 'SKILL.md') -Value "---`nname: '$Name'`ndescription: 'Synthetic fixture.'`n---`n# Fixture"
        $Record = @{ id = $Name; version = '1.0.0' }
        foreach ($Key in $Changes.Keys) { $Record[$Key] = $Changes[$Key] }
        $Record | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Directory 'skill.metadata.yaml')
        return $Record
    }

    function Invoke-FixtureValidation {
        param([string]$Root, [string[]]$Names = @(), [string[]]$Selections = @())
        Invoke-SkillValidation -RepoRoot $Root -SkillName $Names -OptionalSelection $Selections -PythonPath $script:Python
    }
}

Describe 'Skill metadata validation' -Tag 'Unit' {
    BeforeEach {
        $script:Root = New-MetadataFixture
        $script:Record = Set-FixtureSkill -Root $script:Root
    }

    It 'accepts omitted collections and skips unconverted directories' {
        [void](New-Item -ItemType Directory -Path (Join-Path $script:Root '.github/skills/unconverted'))
        $Result = Invoke-FixtureValidation $script:Root
        $Result.CatalogCount | Should -Be 1
        @($Result.SelectedIds).Count | Should -Be 1
    }

    It 'preserves exact UTF-8 bytes including CRLF across the bounded input boundary' {
        $Path = Join-Path $TestDrive 'bytes.yaml'
        $Expected = [byte[]]@(0x23, 0x20, 0xc3, 0xa9, 0x0d, 0x0a)
        [IO.File]::WriteAllBytes($Path, $Expected)
        (Read-SkillInputBytes -Path $Path) | Should -Be $Expected
    }

    It 'accepts an empty source and exactly one MiB at the bounded input boundary' {
        $Path = Join-Path $TestDrive 'boundary.yaml'
        foreach ($Length in @(0, 1048576)) {
            [IO.File]::WriteAllBytes($Path, [byte[]]::new($Length))
            (Read-SkillInputBytes -Path $Path).Length | Should -Be $Length
        }
    }

    It 'rejects oversized metadata before starting the Python reader' {
        $Path = Join-Path $TestDrive 'oversized.yaml'
        [IO.File]::WriteAllBytes($Path, [byte[]]::new(1048577))
        Mock Invoke-LibraryProcess { throw 'The reader must not start.' }
        { Read-SkillYaml -Path $Path -PythonPath $script:Python } | Should -Throw '*1 MiB*'
        Should -Invoke Invoke-LibraryProcess -Times 0 -Exactly
    }

    It 'rejects file-path arguments to the stdin-only Python reader' {
        $Executable = (Get-Command $script:Python -CommandType Application -TotalCount 1).Source
        $Path = Join-Path $TestDrive 'not-an-input.yaml'
        Set-Content -LiteralPath $Path -Value 'SYNTHETIC_NOT_READER_INPUT'
        $Result = Invoke-LibraryProcess -Executable $Executable -Arguments @(
            '-I', '-B', (Join-Path $PSScriptRoot '../Read-Metadata.py'), $Path
        ) -InputBytes ([Text.Encoding]::UTF8.GetBytes('id: example-skill'))
        $Result.ExitCode | Should -Be 2
        $Result.Bytes.Length | Should -Be 0
    }

    It 'treats a path-like YAML scalar as data rather than another input file' {
        $Path = Join-Path $TestDrive 'path-scalar.yaml'
        Set-Content -LiteralPath $Path -Value '/synthetic/not-reader-input.yaml'
        Read-SkillYaml -Path $Path -PythonPath $script:Python | Should -Be '/synthetic/not-reader-input.yaml'
    }

    It 'isolates trusted Python imports from inherited paths and snapshot payloads' {
        $Injection = Join-Path $TestDrive 'synthetic-imports'
        [void][IO.Directory]::CreateDirectory($Injection)
        [IO.File]::WriteAllText((Join-Path $Injection 'sitecustomize.py'), 'raise SystemExit("SYNTHETIC_IMPORT_EXECUTED")')
        [IO.File]::WriteAllText((Join-Path $Injection 'yaml.py'), 'raise RuntimeError("SYNTHETIC_IMPORT_EXECUTED")')
        $Previous = [Environment]::GetEnvironmentVariable('PYTHONPATH')
        try {
            $env:PYTHONPATH = $Injection
            (Invoke-FixtureValidation $script:Root).CatalogCount | Should -Be 1
            @(Get-ChildItem -LiteralPath $Injection -Recurse -Filter '*.pyc' -Force).Count | Should -Be 0
        }
        finally { [Environment]::SetEnvironmentVariable('PYTHONPATH', $Previous) }
    }

    It 'validates the <Name> template against the authoritative schema' -ForEach @(
        @{ Name = 'metadata.yaml.tmpl' }
        @{ Name = 'metadata-full.yaml.tmpl' }
    ) {
        $Template = Read-SkillYaml -Path (Join-Path $PSScriptRoot "../../examples/$Name") -PythonPath $script:Python
        Test-Json -Json (ConvertTo-Json -InputObject $Template -Depth 20) -SchemaFile $script:Schema | Should -BeTrue
    }

    It 'resolves the complete example with synthetic dependencies and declared files' {
        [void](Set-FixtureSkill -Root $script:Root -Name 'example-dependency')
        [void](Set-FixtureSkill -Root $script:Root -Name 'example-extra')
        [void][IO.Directory]::CreateDirectory((Join-Path $script:Root 'docs'))
        foreach ($Name in @('example-NOTICE.txt', 'example-external-NOTICE.txt', 'example-instructions.md')) {
            Set-Content -LiteralPath (Join-Path $script:Root "docs/$Name") -Value 'Synthetic reviewed input.'
        }
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../examples/metadata-full.yaml.tmpl') `
            -Destination (Join-Path $script:Root '.github/skills/example-skill/skill.metadata.yaml')
        $Result = Invoke-FixtureValidation $script:Root -Names example-skill -Selections example-skill/extra-guidance
        $Result.SelectedIds -join ',' | Should -Be 'example-dependency,example-extra,example-skill'
    }

    It 'rejects invalid closed-schema field <Label>' -ForEach @(
        @{ Label = 'unknown'; Changes = @{ unexpected = $true } }
        @{ Label = 'removed resources'; Changes = @{ resources = @() } }
        @{ Label = 'schemaVersion'; Changes = @{ schemaVersion = 1 } }
        @{ Label = 'null array'; Changes = @{ required = $null } }
        @{ Label = 'object array'; Changes = @{ required = @{} } }
        @{ Label = 'numeric version'; Changes = @{ version = 1 } }
        @{ Label = 'range dependency'; Changes = @{ required = @(@{ id = 'other'; version = '>=1.0.0' }) } }
        @{ Label = 'removed entrypoint'; Changes = @{ entrypoint = 'SKILL.md' } }
        @{ Label = 'removed origin'; Changes = @{ origin = @{ path = '.github/skills/example-skill' } } }
        @{ Label = 'removed provenance status'; Changes = @{ provenanceStatus = 'reviewed' } }
        @{ Label = 'null license'; Changes = @{ license = $null } }
        @{ Label = 'empty license'; Changes = @{ license = '' } }
        @{ Label = 'unknown nested property'; Changes = @{ required = @(@{ id = 'other'; version = '1.0.0'; unknown = 1 }) } }
        @{ Label = 'tooling boolean'; Changes = @{ tooling = @(@{ id = 'python'; versionRequirement = '>=3.11.0'; scope = 'authoring'; required = 'true' }) } }
    ) {
        [void](Set-FixtureSkill -Root $script:Root -Changes $Changes)
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*schema validation failed*'
    }

    It 'rejects a missing mandatory field' {
        $script:Record.Remove('version')
        $script:Record | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $script:Root '.github/skills/example-skill/skill.metadata.yaml')
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*schema validation failed*'
    }

    It 'rejects unsafe YAML <Label>' -ForEach @(
        @{ Label = 'duplicate keys'; Text = "id: one`nid: two" }
        @{ Label = 'custom tag'; Text = 'id: !custom value' }
        @{ Label = 'explicit tag'; Text = 'id: !!str value' }
        @{ Label = 'aliases'; Text = "first: &value []`nsecond: *value" }
        @{ Label = 'merge'; Text = "<<: {id: value}" }
        @{ Label = 'timestamp'; Text = 'date: 2026-01-01' }
        @{ Label = 'nonfinite'; Text = 'value: .nan' }
        @{ Label = 'multiple documents'; Text = "id: one`n---`nid: two" }
        @{ Label = 'complex keys'; Text = '? [a, b]' }
    ) {
        Set-Content (Join-Path $script:Root '.github/skills/example-skill/skill.metadata.yaml') $Text
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*YAML reader failed*'
    }

    It 'preserves empty and singleton arrays, booleans, integers and nulls' {
        $Path = Join-Path $TestDrive 'scalars.yaml'
        Set-Content $Path "empty: []`none: [true]`nvalues: [false, 1, null]"
        $Value = Read-SkillYaml -Path $Path -PythonPath $script:Python
        $Value.empty.Count | Should -Be 0
        $Value.one.Count | Should -Be 1
        $Value.one[0] | Should -BeOfType ([bool])
        $Value.values[0] | Should -BeOfType ([bool])
        $Value.values[1] | Should -BeOfType ([long])
        $Value.values[2] | Should -BeNullOrEmpty
    }

    It 'resolves required dependencies before their consumer' {
        [void](Set-FixtureSkill -Root $script:Root -Name 'dependency')
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ required = @(@{ id = 'dependency'; version = '1.0.0' }) })
        $Result = Invoke-FixtureValidation $script:Root -Names example-skill
        $Result.SelectedIds -join ',' | Should -Be 'dependency,example-skill'
    }

    It 'includes optional edges only through explicit reachable selection' {
        [void](Set-FixtureSkill -Root $script:Root -Name 'dependency')
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ optional = @(@{ id = 'dependency'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic opt-in.' }) })
        (Invoke-FixtureValidation $script:Root -Names example-skill).SelectedIds.Count | Should -Be 1
        (Invoke-FixtureValidation $script:Root -Names example-skill -Selections example-skill/extra).SelectedIds.Count | Should -Be 2
        { Invoke-FixtureValidation $script:Root -Names dependency -Selections example-skill/extra } | Should -Throw '*not reachable*'
        { Invoke-FixtureValidation $script:Root -Selections example-skill/typo } | Should -Throw '*Unknown or duplicate*'
    }

    It 'rejects missing dependency IDs and unavailable exact versions' {
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ required = @(@{ id = 'dependency'; version = '2.0.0' }) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Missing dependency*'
        [void](Set-FixtureSkill -Root $script:Root -Name 'dependency')
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*version mismatch*'
    }

    It 'rejects duplicate IDs, duplicate edges and required/optional overlaps' {
        [void](Set-FixtureSkill -Root $script:Root -Name 'dependency' -Changes @{ id = 'example-skill' })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Duplicate component ID*'
        [void](Set-FixtureSkill -Root $script:Root -Name 'dependency')
        $Edge = @{ id = 'dependency'; version = '1.0.0' }
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ required = @($Edge, $Edge) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Duplicate dependency*'
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ required = @($Edge); optional = @(@{ id = 'dependency'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic.' }) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*overlap*'
    }

    It 'rejects required cycles and explicitly selected optional cycles' {
        [void](Set-FixtureSkill -Root $script:Root -Name 'dependency' -Changes @{ required = @(@{ id = 'example-skill'; version = '1.0.0' }) })
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ required = @(@{ id = 'dependency'; version = '1.0.0' }) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*cycle*'
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ optional = @(@{ id = 'dependency'; version = '1.0.0'; selectionKey = 'extra'; reason = 'Synthetic.' }) })
        (Invoke-FixtureValidation $script:Root -Names example-skill).SelectedIds.Count | Should -Be 1
        { Invoke-FixtureValidation $script:Root -Names example-skill -Selections example-skill/extra } | Should -Throw '*cycle*'
    }

    It 'rejects unsafe or missing external path <Value>' -ForEach @(
        @{ Value = '../escape.md' }
        @{ Value = '/absolute.md' }
        @{ Value = 'folder\file.md' }
        @{ Value = 'C:/file.md' }
        @{ Value = 'missing.md' }
    ) {
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ externalFiles = @(@{ path = $Value; kind = 'instruction'; loadingPurpose = 'Synthetic.' }) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw
    }

    It 'rejects missing entrypoints and native identity mismatches' {
        Set-Content (Join-Path $script:Root '.github/skills/example-skill/SKILL.md') "---`nname: wrong`ndescription: 'Synthetic.'`n---"
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*frontmatter*'
        Remove-Item (Join-Path $script:Root '.github/skills/example-skill/SKILL.md')
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Missing declared path*'
    }

    It 'rejects internal external-file declarations and duplicate notice paths' {
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ externalFiles = @(@{ path = '.github/skills/example-skill/SKILL.md'; kind = 'instruction'; loadingPurpose = 'Synthetic.' }) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*implicit content*'
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ notices = @('LICENSE', 'license') })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Duplicate declared path*'
    }

    It 'rejects secret-like local filenames' {
        Set-Content (Join-Path $script:Root '.github/skills/example-skill/.env') 'SYNTHETIC=true'
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Unsafe local input name*'
    }

    It 'rejects case-insensitive collisions on case-sensitive filesystems' -Skip:$IsWindows {
        Set-Content (Join-Path $script:Root '.github/skills/example-skill/A.md') 'Synthetic.'
        Set-Content (Join-Path $script:Root '.github/skills/example-skill/a.md') 'Synthetic.'
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*collision*'
    }

    It 'rejects symlink escapes in content and external path ancestors' -Skip:$IsWindows {
        $Outside = Join-Path $TestDrive 'outside'
        [void](New-Item -ItemType Directory -Path $Outside -Force)
        Set-Content (Join-Path $Outside 'notice.md') 'Synthetic.'
        $Link = Join-Path $script:Root '.github/skills/example-skill/escape'
        [void](New-Item -ItemType SymbolicLink -Path $Link -Target $Outside)
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*symbolic link*'
        Remove-Item -LiteralPath $Link
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $script:Root 'external') -Target $Outside)
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ externalFiles = @(@{ path = 'external/notice.md'; kind = 'notice'; loadingPurpose = 'Synthetic.' }) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*symbolic link*'
    }

    It 'has no publication switch or clearance result' {
        (Get-Command $script:Validator).Parameters.ContainsKey('Publication') | Should -BeFalse
        (Get-Command Invoke-SkillValidation).Parameters.ContainsKey('Publication') | Should -BeFalse
        (Invoke-FixtureValidation $script:Root).PSObject.Properties.Name | Should -Not -Contain 'Publication'
    }

    It 'resolves inherited license and shared notices into the in-memory component only' {
        $MetadataPath = Join-Path $script:Root '.github/skills/example-skill/skill.metadata.yaml'
        $Original = Get-Content -LiteralPath $MetadataPath -Raw
        Mock Read-SkillYaml { $script:Record } -ParameterFilter { $Path -eq (Join-Path $script:Root '.github/skills/example-skill/skill.metadata.yaml') }
        [void](Invoke-FixtureValidation $script:Root)
        $script:Record.license | Should -Be 'MIT'
        $script:Record.notices -join ',' | Should -Be 'LICENSE'
        $script:Record.facets.Count | Should -Be 0
        Get-Content -LiteralPath $MetadataPath -Raw | Should -BeExactly $Original
    }

    It 'accepts a component license override and additive notices without replacing shared notices' {
        Set-Content (Join-Path $script:Root 'NOTICE') 'Synthetic additional notice.'
        $script:Record = Set-FixtureSkill -Root $script:Root -Changes @{ license = 'Apache-2.0'; notices = @('NOTICE') }
        Mock Read-SkillYaml { $script:Record } -ParameterFilter { $Path -eq (Join-Path $script:Root '.github/skills/example-skill/skill.metadata.yaml') }
        (Invoke-FixtureValidation $script:Root).CatalogCount | Should -Be 1
        $script:Record.license | Should -Be 'Apache-2.0'
        $script:Record.notices -join ',' | Should -Be 'LICENSE,NOTICE'
        Remove-Item (Join-Path $script:Root 'LICENSE')
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Missing declared path*'
    }

    It 'rejects null component collection <Collection>' -ForEach @(
        @{ Collection = 'facets' }
        @{ Collection = 'notices' }
        @{ Collection = 'required' }
        @{ Collection = 'optional' }
        @{ Collection = 'externalFiles' }
        @{ Collection = 'tooling' }
    ) {
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ $Collection = $null })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*schema validation failed*'
    }

    It 'rejects invalid repository defaults <Label>' -ForEach @(
        @{ Label = 'unknown property'; Text = "license: MIT`nunknown: true" }
        @{ Label = 'component field'; Text = "license: MIT`nrequired: []" }
        @{ Label = 'missing license'; Text = 'notices: []' }
        @{ Label = 'null license'; Text = 'license: null' }
        @{ Label = 'empty license'; Text = "license: ''" }
        @{ Label = 'null notices'; Text = "license: MIT`nnotices: null" }
        @{ Label = 'object notices'; Text = "license: MIT`nnotices: {}" }
        @{ Label = 'duplicate notices'; Text = "license: MIT`nnotices: [LICENSE, LICENSE]" }
    ) {
        Set-Content (Join-Path $script:Root '.config/skill-library.yaml') $Text
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*defaults schema validation failed*'
    }

    It 'accepts omitted and empty repository notice arrays and explicit empty component arrays' {
        foreach ($Text in @('license: MIT', "license: MIT`nnotices: []")) {
            Set-Content (Join-Path $script:Root '.config/skill-library.yaml') $Text
            [void](Set-FixtureSkill -Root $script:Root -Changes @{ facets = @(); notices = @(); required = @(); optional = @(); externalFiles = @(); tooling = @() })
            (Invoke-FixtureValidation $script:Root).CatalogCount | Should -Be 1
        }
    }

    It 'requires explicit repository defaults without falling back to inferred licensing' {
        Remove-Item (Join-Path $script:Root '.config/skill-library.yaml')
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ license = 'Apache-2.0' })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Missing declared path*'
    }

    It 'uses the restricted reader for defaults' {
        Set-Content (Join-Path $script:Root '.config/skill-library.yaml') "license: MIT`nlicense: Apache-2.0"
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*YAML reader failed*'
    }

    It 'rejects unsafe default and additional notice path <Value>' -ForEach @(
        @{ Value = '../escape.md' }
        @{ Value = '/absolute.md' }
        @{ Value = 'folder\file.md' }
        @{ Value = 'C:/file.md' }
        @{ Value = 'missing.md' }
        @{ Value = '.env' }
    ) {
        Set-Content (Join-Path $script:Root '.env') 'SYNTHETIC=true'
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ notices = @($Value) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw
        [void](Set-FixtureSkill -Root $script:Root)
        @{ license = 'MIT'; notices = @($Value) } | ConvertTo-Json | Set-Content (Join-Path $script:Root '.config/skill-library.yaml')
        { Invoke-FixtureValidation $script:Root } | Should -Throw
    }

    It 'rejects duplicated inherited notices and external paths' {
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ notices = @('LICENSE') })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Duplicate declared path*'
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ externalFiles = @(@{ path = 'LICENSE'; kind = 'notice'; loadingPurpose = 'Synthetic.' }) })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Duplicate declared path*'
        Set-Content (Join-Path $script:Root '.config/skill-library.yaml') "license: MIT`nnotices: [LICENSE, license]"
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*Duplicate declared path*'
    }

    It 'rejects symlinks in defaults, shared notices and additional notice ancestors' -Skip:$IsWindows {
        $Outside = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $Outside)
        Set-Content (Join-Path $Outside 'NOTICE') 'Synthetic.'
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $script:Root 'linked') -Target $Outside)
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ notices = @('linked/NOTICE') })
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*symbolic link*'
        [void](Set-FixtureSkill -Root $script:Root)
        Set-Content (Join-Path $script:Root '.config/skill-library.yaml') "license: MIT`nnotices: [linked/NOTICE]"
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*symbolic link*'
        Move-Item (Join-Path $script:Root '.config/skill-library.yaml') (Join-Path $Outside 'defaults.yaml')
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $script:Root '.config/skill-library.yaml') -Target (Join-Path $Outside 'defaults.yaml'))
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*symbolic link*'
        Remove-Item (Join-Path $script:Root '.config/skill-library.yaml')
        Remove-Item (Join-Path $script:Root '.config') -Force
        Copy-Item (Join-Path $Outside 'defaults.yaml') (Join-Path $Outside 'skill-library.yaml')
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $script:Root '.config') -Target $Outside)
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*symbolic link*'
    }

    It 'derives the native folder independently of the component id' {
        [void](Set-FixtureSkill -Root $script:Root -Changes @{ id = 'distribution-id' })
        (Invoke-FixtureValidation $script:Root -Names example-skill).SelectedIds | Should -Contain 'distribution-id'
    }

    It 'is independent of caller location and supports direct explicit roots' {
        Push-Location $TestDrive
        try {
            (Invoke-FixtureValidation $script:Root).CatalogCount | Should -Be 1
            $Output = & (Get-Process -Id $PID).Path -NoProfile -File $script:Validator -RepoRoot $script:Root -PythonPath $script:Python 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($Output -join ' ')
        }
        finally { Pop-Location }
    }

    It 'reports explicit interpreter failure without leaking its stderr' {
        { Invoke-SkillValidation -RepoRoot $script:Root -PythonPath (Join-Path $TestDrive 'missing-python') } | Should -Throw '*Python unavailable*'
        $Output = & (Get-Process -Id $PID).Path -NoProfile -File $script:Validator -RepoRoot $script:Root -PythonPath (Join-Path $TestDrive 'missing-python') 2>&1
        $LASTEXITCODE | Should -Be 1
        ($Output -join ' ') | Should -Not -Match ([regex]::Escape($TestDrive))
    }

    It 'handles an executable that starts but fails without exposing native stderr' {
        $Output = & (Get-Process -Id $PID).Path -NoProfile -File $script:Validator -RepoRoot $script:Root -PythonPath (Get-Process -Id $PID).Path 2>&1
        $LASTEXITCODE | Should -Be 1
        ($Output -join ' ') | Should -Match 'YAML reader failed'
        ($Output -join ' ') | Should -Not -Match 'Read-Metadata.py|Traceback|ParserError'
    }

    It 'rejects excessive nesting and invalid UTF-8 without echoing input' {
        $Path = Join-Path $script:Root '.github/skills/example-skill/skill.metadata.yaml'
        Set-Content $Path (('[' * 45) + 'SYNTHETIC_INPUT' + (']' * 45))
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*YAML reader failed*'
        [IO.File]::WriteAllBytes($Path, [byte[]]@(255, 254, 253))
        { Invoke-FixtureValidation $script:Root } | Should -Throw '*YAML reader failed*'
    }
}
