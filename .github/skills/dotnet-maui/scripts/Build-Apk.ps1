#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Builds a Release APK of a .NET MAUI Android app for local sideload testing.

.DESCRIPTION
Publishes the app project as a Release APK, then copies it to an output folder under a versioned name and prints its
SHA-256. The version code grows each minute, so a newer build installs over an older one signed with the same key and
keeps the app's sign-in and settings. CI builds made by the shared deploy-maui-android workflow with
version-code-from-clock use the same scheme, so local and CI builds update each other.

The APK is signed with a sideload keystore when one is available:
- ANDROID_SIGNING_KEYSTORE_BASE64 and ANDROID_SIGNING_KEYSTORE_PASSWORD;
- otherwise the Key Vault named by ANDROID_SIGNING_KEY_VAULT, read with the signed-in Azure CLI;
- otherwise this machine's Android debug key.

Signing values reach MSBuild only as environment properties during the build, and the temporary keystore file is
deleted afterwards. A repository calls this script through a root build-apk.ps1 shim that supplies its project and
signing names.

.PARAMETER RepositoryRoot
The application repository root; global.json there selects the SDK.

.PARAMETER Project
The app project path relative to the repository root, for example src/MyApp/MyApp.csproj.

.PARAMETER Name
The APK file name prefix. Defaults to the repository folder name.

.PARAMETER TargetFramework
The Android target framework. Defaults to net10.0-android.

.PARAMETER KeyAlias
The key alias inside the sideload keystore.

.PARAMETER KeyVaultKeystoreSecret
The Key Vault secret holding the base64 keystore.

.PARAMETER KeyVaultPasswordSecret
The Key Vault secret holding the keystore password, which is also the key password.

.PARAMETER OutputDirectory
The folder that receives the APK. Defaults to artifacts/apk under the repository root.

.PARAMETER VersionCode
The Android version code. Defaults to the minutes elapsed since 2025-01-01 UTC, so later builds upgrade earlier ones.

.PARAMETER Install
Installs the APK on a connected emulator or device with adb, replacing an earlier build and keeping its data.

.PARAMETER Device
The adb serial of the target when more than one emulator or device is connected.

.EXAMPLE
./build-apk.ps1

.EXAMPLE
./build-apk.ps1 -Install -Device emulator-5554

.NOTES
Needs the .NET SDK selected by global.json with the maui-android workload, the Android SDK and a JDK; -Install also
needs adb, and Key Vault signing the Azure CLI. Builds take several minutes.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepositoryRoot,
    [string]$Project,
    [string]$Name,
    [string]$TargetFramework = 'net10.0-android',
    [string]$KeyAlias = 'sideload',
    [string]$KeyVaultKeystoreSecret = 'android-sideload-keystore',
    [string]$KeyVaultPasswordSecret = 'android-sideload-keystore-password',
    [string]$OutputDirectory,
    [ValidateRange(2, 2100000000)]
    [int]$VersionCode,
    [switch]$Install,
    [string]$Device
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

#region Native wrappers
function Invoke-DotNet { & dotnet @args }
function Invoke-Git { & git @args }
function Invoke-Adb { & (Resolve-AdbPath) @args }
function Invoke-Aapt2 { & (Resolve-Aapt2Path) @args }
function Invoke-Az { & az @args }
#endregion

#region Signing
function Get-SigningKeystore {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$KeystoreSecret,
        [Parameter(Mandatory)][string]$PasswordSecret
    )

    $base64 = $env:ANDROID_SIGNING_KEYSTORE_BASE64
    $password = $env:ANDROID_SIGNING_KEYSTORE_PASSWORD
    $source = 'environment'
    if (-not $base64 -and $env:ANDROID_SIGNING_KEY_VAULT) {
        $vault = $env:ANDROID_SIGNING_KEY_VAULT
        $failure = "Could not read the signing keystore from Key Vault '$vault'. Sign in with 'az login', or clear ANDROID_SIGNING_KEY_VAULT to sign with the debug key."
        $base64 = (@(Invoke-Az keyvault secret show --vault-name $vault --name $KeystoreSecret --query value -o tsv 2>$null) -join '').Trim()
        if ($LASTEXITCODE -ne 0 -or -not $base64) { throw $failure }
        $password = (@(Invoke-Az keyvault secret show --vault-name $vault --name $PasswordSecret --query value -o tsv 2>$null) -join '').Trim()
        if ($LASTEXITCODE -ne 0 -or -not $password) { throw $failure }
        $source = 'Key Vault'
    }

    if (-not $base64) { return $null }
    if (-not $password) { throw 'ANDROID_SIGNING_KEYSTORE_BASE64 is set without ANDROID_SIGNING_KEYSTORE_PASSWORD.' }

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $path = Join-Path $Directory 'signing.p12'
    try {
        [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($base64))
    }
    catch [FormatException] {
        throw 'The signing keystore is not valid base64.'
    }

    return [pscustomobject]@{ Path = $path; Password = $password; Alias = $Alias; Source = $source }
}

function Set-SigningEnvironment {
    param($Keystore)

    $names = 'AndroidKeyStore', 'AndroidSigningKeyStore', 'AndroidSigningKeyAlias', 'AndroidSigningKeyPass', 'AndroidSigningStorePass'
    if (-not $Keystore) {
        foreach ($name in $names) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
        return
    }

    # MSBuild reads environment variables as properties, so signing values never appear on a command line.
    Set-Item -Path Env:AndroidKeyStore -Value 'true'
    Set-Item -Path Env:AndroidSigningKeyStore -Value $Keystore.Path
    Set-Item -Path Env:AndroidSigningKeyAlias -Value $Keystore.Alias
    Set-Item -Path Env:AndroidSigningKeyPass -Value $Keystore.Password
    Set-Item -Path Env:AndroidSigningStorePass -Value $Keystore.Password
}
#endregion

#region Helpers
function Get-ApkVersionCode {
    param([Parameter(Mandatory)][DateTimeOffset]$Now)

    $epoch = [DateTimeOffset]::new(2025, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $minutes = [Math]::Floor(($Now - $epoch).TotalMinutes)
    if ($minutes -lt 2) { throw 'The clock is earlier than 2025; pass -VersionCode explicitly.' }
    return [int]$minutes
}

function Get-ApkDisplayVersion {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Label = 'local'
    )

    $tag = @(Invoke-Git -C $Root describe --tags --abbrev=0 2>$null)
    $commit = @(Invoke-Git -C $Root rev-parse --short HEAD 2>$null)
    $base = if ($tag.Count -gt 0 -and $tag[0] -match '^\d+\.\d+\.\d+$') { $tag[0] } else { '0.0.0' }
    $suffix = if ($commit.Count -gt 0 -and $commit[0]) { "-$Label.$($commit[0])" } else { "-$Label" }
    return "$base$suffix"
}

function Get-AndroidSdkRoots {
    $sdkRoots = @(@($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT) | Where-Object { $_ })
    if ($env:LOCALAPPDATA) { $sdkRoots += Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    if ($HOME) { $sdkRoots += Join-Path $HOME 'Android/Sdk' }
    return , $sdkRoots
}

function Resolve-AdbPath {
    $onPath = Get-Command -Name adb -CommandType Application -TotalCount 1 -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    foreach ($sdkRoot in (Get-AndroidSdkRoots)) {
        foreach ($name in 'adb.exe', 'adb') {
            $candidate = Join-Path (Join-Path $sdkRoot 'platform-tools') $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw 'adb was not found. Install the Android SDK platform-tools or set ANDROID_HOME.'
}

function Resolve-Aapt2Path {
    foreach ($sdkRoot in (Get-AndroidSdkRoots)) {
        $buildTools = Join-Path $sdkRoot 'build-tools'
        if (-not (Test-Path -LiteralPath $buildTools -PathType Container)) { continue }
        foreach ($version in @(Get-ChildItem -LiteralPath $buildTools -Directory | Sort-Object Name -Descending)) {
            foreach ($name in 'aapt2.exe', 'aapt2') {
                $candidate = Join-Path $version.FullName $name
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            }
        }
    }
    throw 'aapt2 was not found. Install the Android SDK build-tools or set ANDROID_HOME.'
}

function Get-PackagedVersionCode {
    param([Parameter(Mandatory)][string]$Path)

    $badging = @(Invoke-Aapt2 dump badging $Path 2>$null | ForEach-Object { "$_" })
    $package = $badging | Where-Object { $_ -match "^package: .*?\bversionCode='(\d+)'" } | Select-Object -First 1
    if (-not $package) { throw "Could not read the version code of '$Path' with aapt2." }
    $null = $package -match "\bversionCode='(\d+)'"
    return [int]$Matches[1]
}

function Build-Apk {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ApkName,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][int]$Code,
        [Parameter(Mandatory)][string]$DisplayVersion,
        [string]$Framework = 'net10.0-android',
        [string]$Alias = 'sideload',
        [string]$KeystoreSecret = 'android-sideload-keystore',
        [string]$PasswordSecret = 'android-sideload-keystore-password'
    )

    $projectFile = Join-Path $Root $ProjectPath
    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw "The app project '$ProjectPath' was not found under '$Root'." }
    if (-not $PSCmdlet.ShouldProcess($projectFile, "Publish Release APK $DisplayVersion ($Code)")) { return $null }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $publishDirectory = Join-Path $Destination 'publish'
    $signingDirectory = Join-Path $Destination 'signing'
    if (Test-Path -LiteralPath $publishDirectory) { Remove-Item -LiteralPath $publishDirectory -Recurse -Force }
    Push-Location -LiteralPath $Root
    try {
        $keystore = Get-SigningKeystore -Directory $signingDirectory -Alias $Alias -KeystoreSecret $KeystoreSecret -PasswordSecret $PasswordSecret
        Set-SigningEnvironment -Keystore $keystore
        # Run from the root so global.json selects the SDK; without AndroidKeyStore the debug key signs the APK.
        # Clean first: an incremental publish keeps the previous package when only the version changes.
        Invoke-DotNet clean $projectFile -f $Framework -c Release -nologo -v q | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "dotnet clean failed with exit code $LASTEXITCODE." }
        Invoke-DotNet publish $projectFile -f $Framework -c Release -o $publishDirectory -nologo `
            '-p:AndroidPackageFormat=apk' "-p:ApplicationVersion=$Code" "-p:ApplicationDisplayVersion=$DisplayVersion" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE." }
    }
    finally {
        Set-SigningEnvironment -Keystore $null
        if (Test-Path -LiteralPath $signingDirectory) { Remove-Item -LiteralPath $signingDirectory -Recurse -Force }
        Pop-Location
    }

    $signed = @(Get-ChildItem -LiteralPath $publishDirectory -Filter '*-Signed.apk' -File)
    if ($signed.Count -ne 1) { throw "Expected one signed APK in '$publishDirectory' but found $($signed.Count)." }
    $packagedCode = Get-PackagedVersionCode -Path $signed[0].FullName
    if ($packagedCode -ne $Code) { throw "The APK has version code $packagedCode instead of $Code; delete the app's bin and obj folders and build again." }

    $target = Join-Path $Destination "$ApkName-$DisplayVersion-$Code.apk"
    Copy-Item -LiteralPath $signed[0].FullName -Destination $target -Force
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
    return [pscustomobject]@{
        Path           = $target
        Sha256         = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        VersionCode    = $Code
        DisplayVersion = $DisplayVersion
        SignedWith     = if ($keystore) { "sideload keystore ($($keystore.Source))" } else { 'this machine''s debug key' }
    }
}

function Install-Apk {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Serial
    )

    $target = if ($Serial) { $Serial } else { 'the connected device' }
    if (-not $PSCmdlet.ShouldProcess($target, 'Install APK, keeping app data')) { return }

    $arguments = @()
    if ($Serial) { $arguments += '-s', $Serial }
    $arguments += 'install', '-r', $Path
    $output = @(Invoke-Adb @arguments 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0 -or -not ($output -match '^Success')) {
        $last = if ($output.Count -gt 0) { $output[-1] } else { 'no output' }
        $hint = if ($output -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') { ' A build signed with another key must be uninstalled first, which deletes its data.' } else { '' }
        throw "adb install failed: $last.$hint"
    }
}
#endregion

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not $RepositoryRoot -or -not $Project) { throw 'Pass -RepositoryRoot and -Project; a repository build-apk.ps1 shim supplies both.' }
        $root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
        $apkName = if ($Name) { $Name } else { Split-Path $root -Leaf }
        $destination = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $root 'artifacts/apk' }
        $code = if ($PSBoundParameters.ContainsKey('VersionCode')) { $VersionCode } else { Get-ApkVersionCode -Now ([DateTimeOffset]::UtcNow) }
        $displayVersion = Get-ApkDisplayVersion -Root $root

        $apk = Build-Apk -Root $root -ProjectPath $Project -ApkName $apkName -Destination $destination -Code $code `
            -DisplayVersion $displayVersion -Framework $TargetFramework -Alias $KeyAlias `
            -KeystoreSecret $KeyVaultKeystoreSecret -PasswordSecret $KeyVaultPasswordSecret
        if ($apk) {
            Write-Host "APK:     $($apk.Path)"
            Write-Host "Version: $($apk.DisplayVersion) ($($apk.VersionCode))"
            Write-Host "SHA-256: $($apk.Sha256)"
            Write-Host "Signed:  $($apk.SignedWith)"
            if ($Install) {
                Install-Apk -Path $apk.Path -Serial $Device
                Write-Host "Installed: $(if ($Device) { $Device } else { 'the connected device' })"
            }
        }
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue $_
        exit 1
    }
}
