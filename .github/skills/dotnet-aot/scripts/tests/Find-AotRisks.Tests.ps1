#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    $script:Scanner = Join-Path $PSScriptRoot '..\Find-AotRisks.ps1'
    $script:Pwsh = (Get-Command pwsh -CommandType Application -TotalCount 1).Source
    function Invoke-Scan {
        param([string]$InputPath, [string]$FailOn = 'Never')
        $output = @(& $script:Pwsh -NoProfile -File $script:Scanner -Path $InputPath -Format Json -FailOn $FailOn 2>&1)
        [pscustomobject]@{ Code = $LASTEXITCODE; Text = $output -join "`n" }
    }
}

Describe 'Native AOT lexical scan' {
    It 'returns an empty JSON array for a clean source file' {
        $file = Join-Path $TestDrive 'Clean.cs'
        Set-Content -LiteralPath $file -Value 'public sealed class Clean;'
        $result = Invoke-Scan $file
        $result.Code | Should -Be 0
        $result.Text.Trim() | Should -Be '[]'
    }

    It 'preserves array shape and exact finding fields for one match' {
        $file = Join-Path $TestDrive 'Endpoint.cs'
        Set-Content -LiteralPath $file -Value "// heading`nservices.AddControllers(); // private-source-marker"
        $result = Invoke-Scan $file
        $result.Code | Should -Be 0
        $result.Text.TrimStart() | Should -Match '^\['
        $data = ConvertFrom-Json -InputObject $result.Text -NoEnumerate
        $data.Count | Should -Be 1
        ($data[0].PSObject.Properties.Name -join ',') | Should -Be 'Rule,Severity,Path,Line,Message'
        $data[0].Rule | Should -Be 'AOT001'
        $data[0].Severity | Should -Be 'review'
        $data[0].Line | Should -Be 2
        $data[0].Path | Should -Be $file
        $result.Text | Should -Not -Match 'private-source-marker'
    }

    It 'supports an explicit finding exit code without calling it a compiler error' {
        $file = Join-Path $TestDrive 'Emit.cs'
        Set-Content -LiteralPath $file -Value 'var method = new DynamicMethod();'
        $result = Invoke-Scan $file 'Finding'
        $result.Code | Should -Be 2
        $result.Text | Should -Match 'AOT002'
    }

    It 'skips generated and dependency directories and generated source files' {
        $root = Join-Path $TestDrive 'skip'
        foreach ($name in @('obj', 'bin', 'deps', 'vendor', '.git', 'node_modules')) {
            $directory = New-Item -ItemType Directory -Path (Join-Path $root $name) -Force
            Set-Content -LiteralPath (Join-Path $directory.FullName 'Hidden.cs') -Value 'services.AddControllers();'
        }
        Set-Content -LiteralPath (Join-Path $root 'Hidden.g.cs') -Value 'services.AddControllers();'
        $result = Invoke-Scan $root
        $result.Code | Should -Be 0
        $result.Text.Trim() | Should -Be '[]'
    }

    It 'fails visibly on missing or unsupported input' -ForEach @('missing.cs', 'unsupported.txt') {
        $file = Join-Path $TestDrive $_
        if ($_ -eq 'unsupported.txt') { Set-Content -LiteralPath $file -Value 'unused' }
        $result = Invoke-Scan $file
        $result.Code | Should -Be 1
        $result.Text | Should -Match 'AOT scan failed'
        $result.Text | Should -Not -Match '^\s*\['
    }

    It 'reports each documented risk category' -ForEach @(
        @{ Rule = 'AOT001'; Source = 'public class Endpoint : ControllerBase {}' }
        @{ Rule = 'AOT002'; Source = 'Assembly.LoadFile(path);' }
        @{ Rule = 'AOT003'; Source = 'type.MakeGenericType(arguments);' }
        @{ Rule = 'AOT004'; Source = 'dynamic value = input;' }
        @{ Rule = 'AOT005'; Source = 'JsonSerializer.Deserialize<Payload>(json);' }
        @{ Rule = 'AOT006'; Source = 'config.Get<Settings>();' }
        @{ Rule = 'AOT007'; Source = '<PackageReference Include="Microsoft.EntityFrameworkCore" />' }
        @{ Rule = 'AOT008'; Source = '<PackageReference Include="protobuf-net.Grpc" />' }
        @{ Rule = 'AOT009'; Source = 'new JsonStringEnumConverter();' }
        @{ Rule = 'AOT010'; Source = '<EnableAotAnalyzer>false</EnableAotAnalyzer>' }
        @{ Rule = 'AOT011'; Source = 'services.AddOpenIdConnect();' }
    ) {
        $file = Join-Path $TestDrive "$Rule.cs"
        Set-Content -LiteralPath $file -Value $Source
        $result = Invoke-Scan $file
        $result.Code | Should -Be 0
        $data = @(ConvertFrom-Json -InputObject $result.Text)
        $data.Rule | Should -Contain $Rule
    }

    It 'does not modify the source while scanning' {
        $file = Join-Path $TestDrive 'Unchanged.props'
        Set-Content -LiteralPath $file -Value '<EnableTrimAnalyzer>false</EnableTrimAnalyzer>'
        $before = (Get-FileHash -LiteralPath $file).Hash
        $null = Invoke-Scan $file
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $before
    }

    It 'deduplicates overlapping input roots' {
        . $script:Scanner
        $root = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'overlap')
        $file = Join-Path $root.FullName 'Controller.cs'
        Set-Content -LiteralPath $file -Value 'services.AddControllers();'
        $findings = @(Find-AotRisk -InputPath @($root.FullName, $file))
        $findings.Count | Should -Be 1
    }

    It 'does not follow linked directories and rejects explicitly linked inputs' {
        $root = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'links')
        $outside = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'outside')
        Set-Content -LiteralPath (Join-Path $outside.FullName 'Controller.cs') -Value 'services.AddControllers();'
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        $link = New-Item -ItemType $linkType -Path (Join-Path $root.FullName 'linked') -Target $outside.FullName
        $result = Invoke-Scan $root.FullName
        $result.Code | Should -Be 0
        $result.Text.Trim() | Should -Be '[]'
        $result = Invoke-Scan $link.FullName
        $result.Code | Should -Be 1
        $result.Text | Should -Match 'Linked scan input'
    }
}
