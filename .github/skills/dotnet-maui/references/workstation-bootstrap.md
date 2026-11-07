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

1. Enable the **Windows Hypervisor Platform** optional feature and reboot if it was off.
2. Check free space before downloading. A current `x86_64` system image downloads as a compressed
   archive of about 2 GB, which then extracts beside it. The emulator itself is about 1 GB, and a
   virtual device's data and snapshots grow to several more. Allow at least 15 GB on the SDK's drive:

   ```powershell
   Get-PSDrive -PSProvider FileSystem | Where-Object Used |
       Select-Object Name, @{ n = 'FreeGB'; e = { [math]::Round($_.Free / 1GB, 1) } }
   ```

   On a small system drive, install the SDK on another drive and set `ANDROID_HOME`,
   `ANDROID_AVD_HOME` and the IDE's Android SDK location to match. When space runs out, `sdkmanager`
   reports `There is not enough space on the disk` and then `Package path is not valid`, leaving an
   empty `system-images\<api>\<tag>\<abi>` folder. Delete that folder before retrying, or `sdkmanager`
   treats the image as installed.
3. Confirm hardware acceleration and the GPU the emulator can use:

   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -accel-check   # expect "WHPX ... is installed and usable"
   Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
   ```

4. Install the emulator and an `x86_64` system image for the app's target API. `sdkmanager` and
   `avdmanager` exit 1 with no output when `JAVA_HOME` is unset, which is common in a fresh shell
   even after the JDK MSI, so set it for the process first:

   ```powershell
   $env:JAVA_HOME = (Get-ChildItem 'C:\Program Files\Microsoft\jdk-*' -Directory |
       Sort-Object Name -Descending | Select-Object -First 1).FullName
   $sdk = "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin"
   & "$sdk\sdkmanager.bat" 'emulator' 'platform-tools' 'system-images;android-36;google_apis;x86_64'
   & "$sdk\avdmanager.bat" create avd -n phone-api36 -d <device-profile> -k 'system-images;android-36;google_apis;x86_64'
   ```

   List device profiles with `avdmanager list device -c` and pick one close to the target phones.
   Choose a `google_apis_playstore` image only when the test needs Play services. Visual Studio's
   **Tools > Android > Android Device Manager** does the same interactively.
5. Tune the virtual device before its first boot. `avdmanager` can create it with the GPU disabled and
   2 GB of RAM. The emulator then renders on the CPU, so it hangs, stops responding or exits with
   `DisplaySurfaceGlContextHelper` or snapshot `gfxstream` errors:

   ```powershell
   $cfg = "$env:USERPROFILE\.android\avd\phone-api36.avd\config.ini"   # or $env:ANDROID_AVD_HOME
   (Get-Content $cfg) -replace '^hw.gpu.enabled = .*', 'hw.gpu.enabled = yes' `
       -replace '^hw.gpu.mode = .*', 'hw.gpu.mode = host' `
       -replace '^hw.ramSize = .*', 'hw.ramSize = 4096' `
       -replace '^vm.heapSize = .*', 'vm.heapSize = 512M' | Set-Content $cfg
   ```

   Keep `hw.cpu.ncore` at 4 and leave at least 8 GB of host RAM free. Avoid `-gpu swiftshader_indirect`,
   which renders on the CPU; use `-gpu host` even with only integrated graphics.
6. Start it from the IDE device list, or cold-boot it from a terminal that stays open, such as a
   background job:

   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd phone-api36 -no-snapshot-load `
       -no-snapshot-save -no-boot-anim -gpu host -memory 4096 -dns-server 1.1.1.1,8.8.8.8
   ```

   A cold boot avoids a snapshot saved under different graphics settings. Explicit DNS servers fix
   browser sign-in pages that report a host "cannot be contacted". Wait for the boot to finish, which
   takes about 20 to 30 seconds with acceleration, then check network access from the device:

   ```powershell
   $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
   & $adb wait-for-device
   while (((& $adb shell getprop sys.boot_completed) -join '').Trim() -ne '1') { Start-Sleep 3 }
   & $adb devices
   & $adb shell ping -c 1 login.microsoftonline.com
   ```

   If it hangs, run `adb emu kill` or stop the shell that launched it; restart `adb` with
   `adb kill-server` and `adb start-server` if `adb devices` lists nothing.
7. Prepare it for scripted testing. Turn off animations so taps and UI dumps settle quickly, and turn off
   stylus handwriting, which otherwise intercepts `adb shell input text`:

   ```powershell
   foreach ($s in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
       & $adb shell settings put global $s 0
   }
   & $adb shell settings put secure stylus_handwriting_enabled 0
   ```

   The first browser launch shows Chrome's first-run screens; complete them once by hand. Sign-in
   pages may raise Chrome's saved-password sheet; dismiss it with `adb shell input keyevent
   KEYCODE_BACK` rather than choosing an account.

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
