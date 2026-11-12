#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../Build-Apk.ps1')
}

Describe 'Get-ApkVersionCode' {
    It 'Counts whole minutes since 2025-01-01 UTC' {
        $now = [DateTimeOffset]::new(2025, 1, 2, 0, 0, 59, [TimeSpan]::Zero)
        Get-ApkVersionCode -Now $now | Should -Be 1440
    }

    It 'Grows with time so later builds upgrade earlier ones' {
        $earlier = Get-ApkVersionCode -Now ([DateTimeOffset]::new(2026, 11, 7, 18, 0, 0, [TimeSpan]::Zero))
        $later = Get-ApkVersionCode -Now ([DateTimeOffset]::new(2026, 11, 7, 18, 1, 0, [TimeSpan]::Zero))
        $later | Should -BeGreaterThan $earlier
    }

    It 'Rejects a clock before the epoch' {
        { Get-ApkVersionCode -Now ([DateTimeOffset]::new(2024, 12, 31, 0, 0, 0, [TimeSpan]::Zero)) } | Should -Throw '*-VersionCode*'
    }
}

Describe 'Get-ApkDisplayVersion' {
    It 'Combines the latest release tag and the commit' {
        Mock Invoke-Git { if ($args -contains 'describe') { '1.2.3' } else { 'abc1234' } }
        Get-ApkDisplayVersion -Root $TestDrive | Should -Be '1.2.3-local.abc1234'
    }

    It 'Falls back when there is no release tag or commit' {
        Mock Invoke-Git { }
        Get-ApkDisplayVersion -Root $TestDrive | Should -Be '0.0.0-local'
    }

    It 'Uses the given label' {
        Mock Invoke-Git { if ($args -contains 'describe') { '1.2.3' } else { 'abc1234' } }
        Get-ApkDisplayVersion -Root $TestDrive -Label 'ci' | Should -Be '1.2.3-ci.abc1234'
    }
}

Describe 'Build-Apk' {
    BeforeEach {
        $root = Join-Path $TestDrive 'repo'
        $projectFolder = Join-Path $root 'src/ExampleApp'
        New-Item -ItemType Directory -Path $projectFolder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectFolder 'ExampleApp.csproj') -Value '<Project />'
        $destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Apk = @{
            Root           = $root
            ProjectPath    = 'src/ExampleApp/ExampleApp.csproj'
            ApkName        = 'example-app'
            Destination    = $destination
            Code           = 42
            DisplayVersion = '0.0.0-local'
        }
        $script:PublishDirectory = Join-Path $destination 'publish'
        $script:PublishArguments = $null
        $script:Commands = @()
        Mock Invoke-Aapt2 { "package: name='app' versionCode='42' versionName='x'" }
        $script:SavedSigning = @{}
        foreach ($name in 'ANDROID_SIGNING_KEYSTORE_BASE64', 'ANDROID_SIGNING_KEYSTORE_PASSWORD', 'ANDROID_SIGNING_KEY_VAULT') {
            $script:SavedSigning[$name] = [Environment]::GetEnvironmentVariable($name)
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
        $script:SigningDuringPublish = $null
        $script:PublishingDotNet = {
            $global:LASTEXITCODE = 0
            if ($args[0] -ne 'publish') { return }
            $script:SigningDuringPublish = @{
                KeyStore = $env:AndroidKeyStore
                Path     = $env:AndroidSigningKeyStore
                Exists   = $env:AndroidSigningKeyStore -and (Test-Path -LiteralPath $env:AndroidSigningKeyStore)
                Alias    = $env:AndroidSigningKeyAlias
                Password = $env:AndroidSigningStorePass
            }
            New-Item -ItemType Directory -Path $script:PublishDirectory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:PublishDirectory 'app-Signed.apk') -Value 'apk'
        }
    }

    AfterEach {
        foreach ($name in $script:SavedSigning.Keys) {
            if ($script:SavedSigning[$name]) { Set-Item -Path "Env:$name" -Value $script:SavedSigning[$name] }
            else { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
        }
    }

    It 'Publishes a Release APK of the project and copies it under a versioned name' {
        Mock Invoke-DotNet {
            $global:LASTEXITCODE = 0
            $script:Commands += $args[0]
            if ($args[0] -ne 'publish') { return }
            $script:PublishArguments = @($args)
            New-Item -ItemType Directory -Path $script:PublishDirectory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:PublishDirectory 'app-Signed.apk') -Value 'apk'
            'Build succeeded.'
        }

        $apk = @(Build-Apk @script:Apk -DisplayVersion '1.2.3-local.abc1234' -Framework 'net11.0-android')

        $apk.Count | Should -Be 1 -Because 'build output must not leak into the result'
        $apk = $apk[0]
        $script:Commands | Should -Be @('clean', 'publish')
        $script:PublishArguments[1] | Should -BeLike '*ExampleApp.csproj'
        $script:PublishArguments | Should -Contain 'net11.0-android'
        $script:PublishArguments | Should -Contain '-p:AndroidPackageFormat=apk'
        $script:PublishArguments | Should -Contain '-p:ApplicationVersion=42'
        $script:PublishArguments | Should -Contain '-p:ApplicationDisplayVersion=1.2.3-local.abc1234'
        $script:PublishArguments | Should -Contain 'Release'
        $apk.Path | Should -Be (Join-Path $script:Apk.Destination 'example-app-1.2.3-local.abc1234-42.apk')
        Test-Path -LiteralPath $apk.Path | Should -BeTrue
        Test-Path -LiteralPath $script:PublishDirectory | Should -BeFalse
        $apk.Sha256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'Fails when dotnet publish fails' {
        Mock Invoke-DotNet { $global:LASTEXITCODE = if ($args[0] -eq 'publish') { 1 } else { 0 } }
        { Build-Apk @script:Apk } | Should -Throw '*publish failed with exit code 1*'
    }

    It 'Fails when no signed APK is produced' {
        Mock Invoke-DotNet {
            New-Item -ItemType Directory -Path $script:PublishDirectory -Force | Out-Null
            $global:LASTEXITCODE = 0
        }
        { Build-Apk @script:Apk } | Should -Throw '*found 0*'
    }

    It 'Fails when the packaged version code is stale' {
        Mock Invoke-DotNet {
            New-Item -ItemType Directory -Path $script:PublishDirectory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:PublishDirectory 'app-Signed.apk') -Value 'apk'
            $global:LASTEXITCODE = 0
        }
        Mock Invoke-Aapt2 { "package: name='app' versionCode='41' versionName='x'" }
        { Build-Apk @script:Apk } | Should -Throw '*version code 41 instead of 42*'
    }

    It 'Fails when the app project is missing' {
        { Build-Apk @script:Apk -ProjectPath 'src/Missing/Missing.csproj' } | Should -Throw '*Missing.csproj*was not found*'
    }

    It 'Builds nothing with -WhatIf' {
        Mock Invoke-DotNet { }
        Build-Apk @script:Apk -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Invoke-DotNet -Times 0
        Test-Path -LiteralPath $script:Apk.Destination | Should -BeFalse
    }

    It 'Signs with the debug key when no keystore is configured' {
        Mock Invoke-DotNet $script:PublishingDotNet

        $apk = Build-Apk @script:Apk

        $script:SigningDuringPublish.KeyStore | Should -BeNullOrEmpty
        $apk.SignedWith | Should -Be "this machine's debug key"
    }

    It 'Signs with a keystore from the environment and the given alias, and removes it afterwards' {
        $env:ANDROID_SIGNING_KEYSTORE_BASE64 = [Convert]::ToBase64String([byte[]](1, 2, 3))
        $env:ANDROID_SIGNING_KEYSTORE_PASSWORD = 'test-password'
        Mock Invoke-DotNet $script:PublishingDotNet

        $apk = Build-Apk @script:Apk -Alias 'example-sideload'

        $script:SigningDuringPublish.KeyStore | Should -Be 'true'
        $script:SigningDuringPublish.Exists | Should -BeTrue
        $script:SigningDuringPublish.Alias | Should -Be 'example-sideload'
        $script:SigningDuringPublish.Password | Should -Be 'test-password'
        $apk.SignedWith | Should -Be 'sideload keystore (environment)'
        Test-Path -LiteralPath $script:SigningDuringPublish.Path | Should -BeFalse
        $env:AndroidKeyStore | Should -BeNullOrEmpty
        $env:AndroidSigningStorePass | Should -BeNullOrEmpty
    }

    It 'Signs with a keystore from the named Key Vault secrets' {
        $env:ANDROID_SIGNING_KEY_VAULT = 'example-vault'
        Mock Invoke-Az {
            $global:LASTEXITCODE = 0
            if ($args -contains 'example-keystore') { [Convert]::ToBase64String([byte[]](1, 2, 3)) } else { 'vault-password' }
        }
        Mock Invoke-DotNet $script:PublishingDotNet

        $apk = Build-Apk @script:Apk -KeystoreSecret 'example-keystore' -PasswordSecret 'example-password'

        $script:SigningDuringPublish.Password | Should -Be 'vault-password'
        $apk.SignedWith | Should -Be 'sideload keystore (Key Vault)'
        Should -Invoke Invoke-Az -Times 1 -ParameterFilter { $args -contains 'example-vault' -and $args -contains 'example-keystore' }
        Should -Invoke Invoke-Az -Times 1 -ParameterFilter { $args -contains 'example-vault' -and $args -contains 'example-password' }
    }

    It 'Explains a Key Vault failure' {
        $env:ANDROID_SIGNING_KEY_VAULT = 'example-vault'
        Mock Invoke-Az { $global:LASTEXITCODE = 1 }
        Mock Invoke-DotNet $script:PublishingDotNet

        { Build-Apk @script:Apk } | Should -Throw '*az login*'
        Should -Invoke Invoke-DotNet -Times 0
    }

    It 'Rejects a keystore without a password' {
        $env:ANDROID_SIGNING_KEYSTORE_BASE64 = [Convert]::ToBase64String([byte[]](1, 2, 3))
        Mock Invoke-DotNet $script:PublishingDotNet

        { Build-Apk @script:Apk } | Should -Throw '*without ANDROID_SIGNING_KEYSTORE_PASSWORD*'
    }
}

Describe 'Install-Apk' {
    It 'Replaces the installed app on the chosen device' {
        Mock Invoke-Adb { $global:LASTEXITCODE = 0; 'Performing Streamed Install'; 'Success' }
        Install-Apk -Path 'app.apk' -Serial 'emulator-5554'
        Should -Invoke Invoke-Adb -Times 1 -ParameterFilter { ($args -join ' ') -eq '-s emulator-5554 install -r app.apk' }
    }

    It 'Omits the serial when none is given' {
        Mock Invoke-Adb { $global:LASTEXITCODE = 0; 'Success' }
        Install-Apk -Path 'app.apk'
        Should -Invoke Invoke-Adb -Times 1 -ParameterFilter { ($args -join ' ') -eq 'install -r app.apk' }
    }

    It 'Explains a signature mismatch' {
        Mock Invoke-Adb { $global:LASTEXITCODE = 1; 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]' }
        { Install-Apk -Path 'app.apk' } | Should -Throw '*INSTALL_FAILED_UPDATE_INCOMPATIBLE*uninstalled first*'
    }

    It 'Reports a missing device without the signature hint' {
        Mock Invoke-Adb { $global:LASTEXITCODE = 1; 'adb.exe: no devices/emulators found' }
        { Install-Apk -Path 'app.apk' } | Should -Throw -ExpectedMessage 'adb install failed: adb.exe: no devices/emulators found.'
    }

    It 'Installs nothing with -WhatIf' {
        Mock Invoke-Adb { }
        Install-Apk -Path 'app.apk' -WhatIf
        Should -Invoke Invoke-Adb -Times 0
    }
}
