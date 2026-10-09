#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Test-DotNetSourceConventions.ps1')

    function New-SyntheticSourceFile {
        param([string] $Name, [string] $Content)
        $path = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        [IO.File]::WriteAllText($path, $Content)
        return [pscustomobject]@{ RelativePath = $Name; FullPath = $path }
    }
}

Describe 'Get-TrackedCSharpFile' -Tag 'Unit' {
    It 'Skips tracked files deleted from the working tree' {
        [IO.File]::WriteAllText((Join-Path $TestDrive 'Existing.cs'), 'public sealed class Existing { }')
        Mock Invoke-AuditGit {
            if ($Arguments[0] -eq 'rev-parse') { return $Root }
            return @('Deleted.cs', 'Existing.cs')
        }

        $files = @(Get-TrackedCSharpFile -Root $TestDrive)

        $files | Should -HaveCount 1
        $files[0].RelativePath | Should -BeExactly 'Existing.cs'
    }
}

Describe 'Get-LayoutFindings' -Tag 'Unit' {
    It 'Allows a nested test double in its owning type file' {
        $file = New-SyntheticSourceFile 'WidgetTests.cs' @'
public sealed class WidgetTests
{
    private sealed class FakeDependency { }
}
'@
        @(Get-LayoutFindings $file) | Should -BeNullOrEmpty
    }

    It 'Reports multiple top-level types in a regular file' {
        $file = New-SyntheticSourceFile 'First.cs' @'
public sealed class First { }
public sealed class Second { }
'@
        $findings = @(Get-LayoutFindings $file)
        $findings.Rule | Should -Contain 'OneTopLevelTypePerFile'
    }

    It 'Allows related types in an underscore config group' {
        $file = New-SyntheticSourceFile '_WidgetConfig.cs' @'
public sealed record WidgetConfig;
public sealed record WidgetChildConfig;
'@
        @(Get-LayoutFindings $file) | Should -BeNullOrEmpty
    }

    It 'Allows enum-only aggregate files' {
        $file = New-SyntheticSourceFile '_Enums.cs' @'
public enum First { One }
internal enum Second { Two }
'@
        @(Get-LayoutFindings $file) | Should -BeNullOrEmpty
    }

    It 'Rejects non-enums in enum aggregate files' {
        $file = New-SyntheticSourceFile '_Enums.cs' 'public sealed class Wrong { }'
        @(Get-LayoutFindings $file).Rule | Should -Contain 'EnumFileContainsNonEnum'
    }

    It 'Accepts generic and partial filenames' {
        $generic = New-SyntheticSourceFile 'Cache{TKey,TValue}.cs' 'public sealed class Cache<TKey, TValue> { }'
        $partial = New-SyntheticSourceFile 'Worker.Logging.cs' 'public sealed partial class Worker { }'
        @(Get-LayoutFindings $generic) | Should -BeNullOrEmpty
        @(Get-LayoutFindings $partial) | Should -BeNullOrEmpty
    }
}

Describe 'Naming and constructor audits' -Tag 'Unit' {
    It 'Reports lowercase public members' {
        $file = New-SyntheticSourceFile 'Widget.cs' @'
public sealed class Widget
{
    public string wrongName { get; init; } = "";
}
'@
        @(Get-NamingFindings $file).Symbol | Should -Contain 'wrongName'
    }

    It 'Reports traditional constructors but not primary constructors' {
        $traditional = New-SyntheticSourceFile 'Traditional.cs' @'
public sealed class Traditional
{
    private readonly string _value;
    public Traditional(string value) { _value = value; }
}
'@
        $primary = New-SyntheticSourceFile 'Primary.cs' 'public sealed class Primary(string value) { }'
        @(Get-ConstructorFindings $traditional).Rule | Should -Contain 'PrimaryConstructorCandidate'
        @(Get-ConstructorFindings $primary) | Should -BeNullOrEmpty
    }

    It 'Ignores parameterless nested constructors and does not attribute them to the containing type' {
        $file = New-SyntheticSourceFile 'Factory.cs' @'
public sealed class Factory
{
    private sealed class Store
    {
        public Store() { }
    }
}
'@
        @(Get-ConstructorFindings $file) | Should -BeNullOrEmpty
    }

    It 'Ignores overloaded constructors' {
        $file = New-SyntheticSourceFile 'ConflictException.cs' @'
public sealed class ConflictException : Exception
{
    public ConflictException() { }
    public ConflictException(Exception innerException) : base("message", innerException) { }
}
'@
        @(Get-ConstructorFindings $file) | Should -BeNullOrEmpty
    }

    It 'Ignores non-public constructors whose accessibility a primary constructor cannot preserve' {
        $file = New-SyntheticSourceFile 'Factory.cs' @'
public abstract class Factory
{
    private readonly string _value;
    protected Factory(string value) { _value = value; }
}
'@
        @(Get-ConstructorFindings $file) | Should -BeNullOrEmpty
    }

    It 'Ignores constructors with behavior beyond dependency capture' {
        $file = New-SyntheticSourceFile 'ValidatedService.cs' @'
public sealed class ValidatedService
{
    private readonly string _value;
    public ValidatedService(string value)
    {
        _value = value;
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
    }
}
'@
        @(Get-ConstructorFindings $file) | Should -BeNullOrEmpty
    }
}

Describe 'Get-LoggingFindings' -Tag 'Unit' {
    It 'Reports lowercase templates and ignores PascalCase' {
        $file = New-SyntheticSourceFile 'Logging.cs' @'
public sealed class Logging
{
    public void Run(ILogger logger)
    {
        logger.LogInformation("{wrongName} {RightName}", 1, 2);
    }
}
'@
        $findings = @(Get-LoggingFindings $file)
        $findings | Should -HaveCount 1
        $findings[0].Symbol | Should -BeExactly 'wrongName'
    }
}
