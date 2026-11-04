# MAUI Workstation Bootstrap

Key steps to take a Windows workstation from nothing to building, testing and debugging a .NET
MAUI app whose product platform is Android. Run commands from the application repository root
unless stated otherwise, so its `global.json` selects the SDK.

## 1. .NET SDK

Install the stable .NET SDK feature band that `global.json` selects, then confirm:

```powershell
dotnet --version
```

## 2. MAUI Workload

Workloads are installed per SDK feature band. Visual Studio installs them only for the band it
bundles, so the command line can still fail with `NETSDK1147` when `global.json` selects another.
From an **elevated** terminal in the repository root:

```powershell
dotnet workload install maui-android   # Android only; use maui for every platform
dotnet workload list                   # must list maui-android for the selected band
```

The install can take many minutes; wait for `Successfully installed workload(s)`.

## 3. Java Development Kit

Install the Microsoft Build of OpenJDK and set `JAVA_HOME` (the MSI offers to set it). The .NET
for Android dependency page recommends OpenJDK 21; the MAUI installation page still names 17.
Either builds .NET 10 Android apps; follow the newer page when they disagree.

## 4. Android SDK

Visual Studio's MAUI workload installs the Android SDK under `%LOCALAPPDATA%\Android\Sdk`. Without
Visual Studio, let the project install exactly what it needs:

```powershell
dotnet build .\src\<App>\<App>.csproj -t:InstallAndroidDependencies -f net10.0-android `
  -p:AndroidSdkDirectory=C:\android-sdk -p:JavaSdkDirectory=C:\jdk -p:AcceptAndroidSDKLicenses=True
```

Use absolute paths without spaces, then set `ANDROID_HOME` to the SDK directory. Rerun the target
after raising the project's Android API level.

## 5. Android Emulator

1. Enable the **Windows Hypervisor Platform** optional feature and reboot if it was off. Check free
   space first: the emulator, one system image and one virtual device need roughly 10 GB. On a small
   system drive, install the SDK on another drive and set `ANDROID_HOME`, `ANDROID_AVD_HOME` and the
   IDE's Android SDK location to match; `sdkmanager` can leave a broken image folder behind when it
   runs out of space, so delete it before retrying.
2. Install the emulator and an `x86_64` system image for the app's target API. `sdkmanager` and
   `avdmanager` need `JAVA_HOME`:

   ```powershell
   $sdk = "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin"
   & "$sdk\sdkmanager.bat" 'emulator' 'system-images;android-36;google_apis;x86_64'
   & "$sdk\avdmanager.bat" create avd -n phone-api36 -d <device-profile> -k 'system-images;android-36;google_apis;x86_64'
   ```

   List device profiles with `avdmanager list device -c` and pick one close to the target phones.
   Choose a `google_apis_playstore` image only when the test needs Play services. Visual Studio's
   **Tools > Android > Android Device Manager** does the same interactively.
3. Start it from the IDE device list, or with
   `& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd phone-api36`, and confirm
   `adb devices` lists it.

## 6. IDE

### Visual Studio 2026

Install the **.NET Multi-platform App UI development** workload. Open the solution, then choose the
framework and target in the debug toolbar: **Windows Machine** for the Windows development target,
or an emulator or paired device for Android.

### VS Code

Install the **.NET MAUI** extension (`ms-dotnettools.dotnet-maui`); it adds C# Dev Kit and C#.
Run **.NET MAUI: Configure Android** from the Command Palette to select the Android SDK and Java SDK
locations if they are not detected. Pick the debug target from the MAUI target selector, then start
debugging. Keep `editorconfig.editorconfig` installed so new files use the repository line endings.

## 7. Verify

```powershell
dotnet workload list
dotnet build .\<Solution>.slnx --configuration Debug
dotnet test --project .\src\<Core>.Tests\<Core>.Tests.csproj
adb devices
```

Ask before running tests or deploying. Then start the Windows target once and deploy to the
emulator once. A physical phone needs developer options and USB or wireless debugging; if it is
enrolled in device management, check that policy before enabling them.
