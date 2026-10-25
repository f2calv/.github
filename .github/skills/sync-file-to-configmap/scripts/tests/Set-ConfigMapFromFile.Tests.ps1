#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Set-ConfigMapFromFile.ps1')
    $script:Git = (Get-Command git -CommandType Application).Source
    $script:Yq = (Get-Command yq -CommandType Application).Source
    function Write-Fixture {
        param([string]$Path, [AllowEmptyString()][string]$Text)
        [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
    }
    function Save-Target {
        $null = Invoke-ConfigMapProcess $script:Git @('-C', $script:TargetRoot, 'add', '--', 'configmap.yaml')
        $Result = Invoke-ConfigMapProcess $script:Git @('-C', $script:TargetRoot, '-c', 'core.hooksPath=',
            '-c', 'commit.gpgsign=false', '-c', 'user.email=test@example.com', '-c', 'user.name=Synthetic Test',
            'commit', '--quiet', '-m', 'synthetic fixture')
        if ($Result.ExitCode -ne 0) { throw 'Synthetic fixture commit failed.' }
    }
    function Read-Target {
        return ,(Read-ConfigMapDocument $script:Yq ([IO.File]::ReadAllText($script:TargetPath)))
    }
}

Describe 'Set-ConfigMapFromFile synthetic regression' {
    BeforeEach {
        $CaseRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        $script:SourceRoot = Join-Path $CaseRoot 'source'
        $script:TargetRoot = Join-Path $CaseRoot 'target'
        $null = New-Item -ItemType Directory -Path $script:SourceRoot, $script:TargetRoot -Force
        $script:SourcePath = Join-Path $script:SourceRoot 'example.txt'
        $script:TargetPath = Join-Path $script:TargetRoot 'configmap.yaml'
        Write-Fixture $script:SourcePath "  café 世界`r`nsecond line`r`n`r`n"
        Write-Fixture $script:TargetPath @'
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-config
  namespace: example
  labels:
    purpose: synthetic
  annotations:
    example.com/note: "preserve me"
data:
  example.txt: old value
  untouched: |
    untouched text
binaryData:
  binary: YWJj
'@
        foreach ($Root in @($script:SourceRoot, $script:TargetRoot)) {
            $null = Invoke-ConfigMapProcess $script:Git @('-C', $Root, 'init', '--quiet')
            $null = Invoke-ConfigMapProcess $script:Git @('-C', $Root, 'config', 'core.autocrlf', 'false')
        }
        Save-Target
        $script:Settings = @{
            SourceRoot = $script:SourceRoot
            SourcePath = 'example.txt'
            TargetRoot = $script:TargetRoot
            TargetPath = 'configmap.yaml'
            ConfigMapName = 'example-config'
            ConfigMapNamespace = 'example'
            DataKey = 'example.txt'
            Format = 'Text'
        }
        $script:Before = [IO.File]::ReadAllBytes($script:TargetPath)
    }

    It 'requires an explicit complete-source non-secret review' {
        { Set-ConfigMapFromFile $script:Settings } | Should -Throw '*non-secret review*'
    }

    It 'validates the full candidate without writing under WhatIf' {
        Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf | Should -BeExactly 'Validated'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:TargetPath)) |
            Should -BeExactly ([Convert]::ToBase64String($script:Before))
    }

    It 'preserves complete Unicode text, trailing newlines and surrounding semantic metadata' {
        $Expected = Read-Target
        $Expected['data']['example.txt'] = [Text.Json.Nodes.JsonValue]::Create("  café 世界`nsecond line`n`n")
        Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false | Should -BeExactly 'Updated'
        [Text.Json.Nodes.JsonNode]::DeepEquals($Expected, (Read-Target)) | Should -BeTrue
        $Status = Invoke-ConfigMapProcess $script:Git @('-C', $script:TargetRoot, 'status', '--porcelain')
        $Status.Output.Trim() | Should -BeExactly 'M configmap.yaml'
    }

    It 'preserves JSONC comments and trailing commas without reserialization' {
        $script:Settings.Format = 'Json'
        $Text = "{`n // synthetic comment`n `"enabled`": true,`n}`n"
        Write-Fixture $script:SourcePath $Text
        Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false | Should -BeExactly 'Updated'
        (Read-Target)['data']['example.txt'].GetValue[string]() | Should -BeExactly $Text
    }

    It 'preserves XML declarations and namespaced KNX root text' {
        $script:Settings.Format = 'Xml'
        $script:Settings.XmlRoot = 'GroupAddress-Export'
        $Text = '<?xml version="1.0" encoding="utf-8"?><GroupAddress-Export xmlns="urn:example"><Item /></GroupAddress-Export>'
        Write-Fixture $script:SourcePath $Text
        Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false | Should -BeExactly 'Updated'
        (Read-Target)['data']['example.txt'].GetValue[string]() | Should -BeExactly $Text
    }

    It 'handles empty, BOM and newline-free text exactly' -ForEach @(
        @{ Text = ''; Expected = '' },
        @{ Text = ([string][char]0xFEFF + 'example'); Expected = 'example' },
        @{ Text = "one`rtwo"; Expected = "one`ntwo" }
    ) {
        Write-Fixture $script:SourcePath $Text
        Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false | Should -BeExactly 'Updated'
        (Read-Target)['data']['example.txt'].GetValue[string]() | Should -BeExactly $Expected
    }

    It 'does not reserialize an already equivalent clean target' {
        Write-Fixture $script:SourcePath 'old value'
        Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false | Should -BeExactly 'Unchanged'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:TargetPath)) |
            Should -BeExactly ([Convert]::ToBase64String($script:Before))
    }

    It 'rejects a second run on a dirty target, then becomes idempotent after commit' {
        $null = Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false } | Should -Throw '*tracked and clean*'
        Save-Target
        Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false | Should -BeExactly 'Unchanged'
    }

    It 'rejects invalid source syntax without leaking parser input' -ForEach @(
        @{ Format = 'Json'; Text = '{"payload-marker": broken}' },
        @{ Format = 'Xml'; Text = '<payload-marker>' },
        @{ Format = 'Xml'; Text = '<!DOCTYPE root [<!ENTITY x SYSTEM "file:///payload-marker">]><root>&x;</root>' },
        @{ Format = 'Xml'; Text = '<?xml version="1.0" encoding="utf-16"?><payload-marker />' }
    ) {
        Write-Fixture $script:SourcePath $Text
        $script:Settings.Format = $Format
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } |
            Should -Throw 'Source format validation failed. Check syntax, encoding and any required XML root locally.'
    }

    It 'rejects a wrong domain XML root' {
        Write-Fixture $script:SourcePath '<different />'
        $script:Settings.Format = 'Xml'
        $script:Settings.XmlRoot = 'GroupAddress-Export'
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw '*Source format validation*'
    }

    It 'rejects invalid UTF-8 and oversized source bytes' {
        [IO.File]::WriteAllBytes($script:SourcePath, [byte[]]@(0xC3, 0x28))
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw '*UTF-8*'
        [IO.File]::WriteAllBytes($script:SourcePath, [byte[]]::new(1MB + 1))
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw '*size limit*'
    }

    It 'rejects total ConfigMap payload above 1 MiB' {
        Write-Fixture $script:SourcePath ('a' * 1MB)
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw '*aggregate 1 MiB*'
    }

    It 'rejects wrong identity, absent key, immutable and non-string data' -ForEach @(
        @{ Old = 'namespace: example'; New = 'namespace: different' },
        @{ Old = 'name: example-config'; New = 'name: other' },
        @{ Old = 'kind: ConfigMap'; New = 'kind: Secret' },
        @{ Old = 'apiVersion: v1'; New = 'apiVersion: example/v1' },
        @{ Old = '  example.txt: old value'; New = '  different: old value' },
        @{ Old = '  example.txt: old value'; New = '  example.txt: 12' },
        @{ Old = 'kind: ConfigMap'; New = "kind: ConfigMap`nimmutable: true" }
    ) {
        Write-Fixture $script:TargetPath ([IO.File]::ReadAllText($script:TargetPath).Replace($Old, $New))
        Save-Target
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw '*ConfigMap identity*'
    }

    It 'rejects multiple documents and duplicate YAML keys' -ForEach @(
        @{ Addition = "`n---`nkind: ConfigMap`n"; Error = '*exactly one*' },
        @{ Addition = "`ndata:`n  example.txt: duplicate`n"; Error = '*Duplicate YAML*' }
    ) {
        Write-Fixture $script:TargetPath ([IO.File]::ReadAllText($script:TargetPath) + $Addition)
        Save-Target
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw $Error
    }

    It 'rejects untracked, staged, modified and Git-hidden target files' -ForEach @(
        @{ Mode = 'untracked' }, @{ Mode = 'staged' }, @{ Mode = 'modified' },
        @{ Mode = 'assume-unchanged' }, @{ Mode = 'skip-worktree' }
    ) {
        switch ($Mode) {
            'untracked' { $null = Invoke-ConfigMapProcess $script:Git @('-C', $script:TargetRoot, 'rm', '--cached', '--quiet', '--', 'configmap.yaml') }
            'staged' {
                [IO.File]::AppendAllText($script:TargetPath, "`n# staged")
                $null = Invoke-ConfigMapProcess $script:Git @('-C', $script:TargetRoot, 'add', '--', 'configmap.yaml')
            }
            'modified' { [IO.File]::AppendAllText($script:TargetPath, "`n# modified") }
            default { $null = Invoke-ConfigMapProcess $script:Git @('-C', $script:TargetRoot, 'update-index', "--$Mode", '--', 'configmap.yaml') }
        }
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw '*tracked and clean*'
    }

    It 'rejects source and target containment escapes' -ForEach @(
        @{ Key = 'SourcePath' }, @{ Key = 'TargetPath' }
    ) {
        $script:Settings[$Key] = '..\outside.txt'
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw '*inside its configured root*'
    }

    It 'rejects directory links both inside and above the configured root' {
        $Link = Join-Path $TestDrive 'linked'
        $Type = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $Type -Path $Link -Target $script:SourceRoot
        { Resolve-ConfigMapPath $Link 'example.txt' } | Should -Throw '*symbolic links or reparse points*'
        $Nested = Join-Path $script:SourceRoot 'nested'
        $null = New-Item -ItemType Directory -Path $Nested
        Write-Fixture (Join-Path $Nested 'text.txt') 'example'
        { Resolve-ConfigMapPath (Join-Path $Link 'nested') 'text.txt' } | Should -Throw '*symbolic links or reparse points*'
        $InnerLink = Join-Path $script:SourceRoot 'link'
        $null = New-Item -ItemType $Type -Path $InnerLink -Target $Nested
        { Resolve-ConfigMapPath $script:SourceRoot 'link\text.txt' } | Should -Throw '*symbolic links or reparse points*'
    }

    It 'loads only ignored untracked local data with explicit overrides and rejects unknown keys' {
        Write-Fixture (Join-Path $script:SourceRoot '.gitignore') "sync.local.psd1`n"
        $Local = Join-Path $script:SourceRoot 'sync.local.psd1'
        Write-Fixture $Local "@{ Format = 'Json'; XmlRoot = '' }"
        $script:Settings.LocalConfigPath = 'sync.local.psd1'
        (Get-ConfigMapSettings $script:Settings $script:Git).Format | Should -BeExactly 'Text'
        Write-Fixture $Local "@{ Unknown = 'example' }"
        { Get-ConfigMapSettings $script:Settings $script:Git } | Should -Throw '*Unsupported local data*'
        Write-Fixture $Local "@{ Format = 'Text' }"
        $null = Invoke-ConfigMapProcess $script:Git @('-C', $script:SourceRoot, 'add', '--force', '--', 'sync.local.psd1')
        { Get-ConfigMapSettings $script:Settings $script:Git } | Should -Throw '*gitignored and untracked*'
    }

    It 'captures tool output in memory and suppresses native error payloads' {
        $Result = Invoke-ConfigMapProcess $script:Yq @('eval', '-p=json', '-o=json', '-I=0', '.', '-') '"café 世界"'
        $Result.Output.Trim() | Should -BeExactly '"café 世界"'
        { Invoke-ConfigMapYq $script:Yq @('eval', '.', '-') 'payload-marker: [' } |
            Should -Throw 'YAML processing failed. Check the manifest and yq version locally.'
        { Invoke-ConfigMapProcess (Join-Path $TestDrive 'missing-tool') @() } |
            Should -Throw 'Local tool execution failed. Check installed tools and retry.'
    }

    It 'rejects an unsupported yq implementation' {
        Mock Invoke-ConfigMapProcess { @{ ExitCode = 0; Output = 'other yq 1.0' } } -ParameterFilter { $Arguments -contains '--version' }
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -WhatIf } | Should -Throw '*Mike Farah yq v4*'
    }

    It 'rejects a candidate that changes surrounding semantic values' {
        $Document = Read-Target
        $Expected = $Document.DeepClone()
        $Expected['metadata']['namespace'] = [Text.Json.Nodes.JsonValue]::Create('different')
        { Assert-ConfigMapCandidate $script:Yq ([IO.File]::ReadAllText($script:TargetPath)) $Expected `
                (Get-ConfigMapSettings $script:Settings $script:Git) 'old value' } | Should -Throw '*surrounding semantic*'
    }

    It 'restores exact original bytes when post-write verification fails' {
        $script:Checks = 0
        Mock Assert-ConfigMapCandidate {
            $script:Checks++
            if ($script:Checks -eq 2) { throw 'Synthetic verification failure.' }
        }
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false } |
            Should -Throw '*original target bytes restored*'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:TargetPath)) |
            Should -BeExactly ([Convert]::ToBase64String($script:Before))
    }

    It 'fails before a write when yq fails during candidate generation' {
        Mock Invoke-ConfigMapYq { throw 'Synthetic tool failure.' } -ParameterFilter { $Arguments -contains '-p=json' }
        { Set-ConfigMapFromFile $script:Settings -ReviewedNonSecret -Confirm:$false } | Should -Throw '*Synthetic tool failure*'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:TargetPath)) |
            Should -BeExactly ([Convert]::ToBase64String($script:Before))
    }
}
