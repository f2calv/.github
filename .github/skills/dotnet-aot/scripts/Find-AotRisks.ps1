#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
    Finds lexical Native AOT review candidates without building or modifying source.
.DESCRIPTION
    Reads C# and MSBuild inputs, skips generated/vendor directories and links, and returns
    locations and generic messages without source snippets. Findings are not compatibility proof.
.PARAMETER Path
    Existing files or directories to inspect.
.PARAMETER Format
    Object emits PowerShell objects; Json always emits an array.
.PARAMETER FailOn
    Finding exits 2 when candidates exist; Never exits 0 after a completed scan.
.EXAMPLE
    ./Find-AotRisks.ps1 -Path ./src -Format Json -FailOn Finding
.NOTES
    Exit codes: 0 completed, 1 scan failure, 2 review candidates under FailOn Finding.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$Path = @('.'),
    [ValidateSet('Object', 'Json')]
    [string]$Format = 'Object',
    [ValidateSet('Never', 'Finding')]
    [string]$FailOn = 'Never'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

#region Scanning
function Find-AotRisk {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$InputPath)

    $rules = @(
        @{ Id = 'AOT001'; Pattern = '\b(AddControllers(?:WithViews)?|AddMvc|MapControllers|ControllerBase)\b|:\s*Controller\b'; Message = 'Review MVC usage and the supported AOT HTTP hosting model.' }
        @{ Id = 'AOT002'; Pattern = '\b(Assembly\s*\.\s*Load\w*|AssemblyLoadContext|Reflection\s*\.\s*Emit|DynamicMethod|AssemblyBuilder|CSharpCompilation)\b'; Message = 'Review dynamic loading or runtime code generation.' }
        @{ Id = 'AOT003'; Pattern = '\b(GetTypes|GetExportedTypes|MakeGenericType|MakeGenericMethod|GetMethod|GetProperty|GetFields)\s*\(|\b(Activator\s*\.\s*CreateInstance|Type\s*\.\s*GetType)\b'; Message = 'Check reflection reachability, bounded types and preservation metadata.' }
        @{ Id = 'AOT004'; Pattern = '\bdynamic\s+\w+'; Message = 'Review runtime dynamic binding on the published path.' }
        @{ Id = 'AOT005'; Pattern = '\bJsonSerializer\s*\.\s*(Serialize|Deserialize)\w*\s*(<|\()'; Message = 'Verify generated JSON context or type-info coverage for this call.' }
        @{ Id = 'AOT006'; Pattern = '\b(Get|GetRequired|Bind|BindConfiguration)\s*(<|\()|\b(ValidateDataAnnotations|ValidateOnStart)\s*\('; Message = 'Check whether configuration binding or validation needs source generation.' }
        @{ Id = 'AOT007'; Pattern = 'Microsoft\.EntityFrameworkCore|\b(DbContext|IQueryable|Expression\s*\.\s*Compile)\b'; Message = 'Verify EF/provider and query-generation support for the exact release.' }
        @{ Id = 'AOT008'; Pattern = 'Castle\.|DynamicProxy|DispatchProxy|protobuf-net|ProtoBuf\.Grpc|Grpc\.Net\.ClientFactory'; Message = 'Verify proxy or RPC dependency AOT support; package presence alone is not a blocker.' }
        @{ Id = 'AOT009'; Pattern = '\bJsonStringEnumConverter\s*\('; Message = 'Review non-generic enum converter compatibility with generated JSON metadata.' }
        @{ Id = 'AOT010'; Pattern = 'UnconditionalSuppressMessage|IL[23]\d{3}|<(EnableAotAnalyzer|EnableTrimAnalyzer|IsTrimmable)>\s*false'; Message = 'Review trimming/AOT suppression or disabled analysis justification.' }
        @{ Id = 'AOT011'; Pattern = '\b(AddRazorPages|AddServerSideBlazor|AddInteractiveServerComponents|AddSignalR|AddSession|AddOpenIdConnect|AddCookie|AddOData)\s*\('; Message = 'Check target-version AOT support for this hosting or authentication feature.' }
    )
    $excluded = @('.git', '.vs', '.idea', 'bin', 'obj', 'node_modules', 'deps', 'vendor', 'packages', 'TestResults')
    $extensions = @('.cs', '.csproj', '.props', '.targets')
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($input in $InputPath) {
        $item = Get-Item -LiteralPath $input -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked scan input is not supported: $input. Supply its explicit source path."
        }
        $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
        if ($item.PSIsContainer) {
            $pending.Push($item)
        }
        elseif ($item.Extension -in $extensions) {
            [void]$files.Add($item.FullName)
        }
        else {
            throw "Unsupported scan input: $input. Supply C# or MSBuild files, or a directory."
        }
        while ($pending.Count -gt 0) {
            foreach ($child in Get-ChildItem -LiteralPath $pending.Pop().FullName -Force) {
                if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($child.PSIsContainer) {
                    if ($child.Name -notin $excluded) { $pending.Push($child) }
                }
                elseif ($child.Extension -in $extensions -and $child.Name -notmatch '\.(g|generated|designer)\.cs$') {
                    [void]$files.Add($child.FullName)
                }
            }
        }
    }

    foreach ($file in $files | Sort-Object) {
        $lineNumber = 0
        foreach ($line in [IO.File]::ReadLines($file)) {
            $lineNumber++
            foreach ($rule in $rules) {
                if ($line -match $rule.Pattern) {
                    [pscustomobject]@{
                        Rule = $rule.Id
                        Severity = 'review'
                        Path = $file
                        Line = $lineNumber
                        Message = $rule.Message
                    }
                }
            }
        }
    }
}
#endregion

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $findings = @(Find-AotRisk -InputPath $Path)
        if ($Format -eq 'Json') { ConvertTo-Json -InputObject $findings -Depth 3 }
        else { $findings }
        if ($FailOn -eq 'Finding' -and $findings.Count -gt 0) { exit 2 }
        exit 0
    }
    catch {
        Write-Error -Message "AOT scan failed: $($_.Exception.Message)" -ErrorAction Continue
        exit 1
    }
}
