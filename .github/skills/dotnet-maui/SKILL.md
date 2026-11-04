---
name: dotnet-maui
description: 'Bootstrap developer workstations for, create, extend and troubleshoot .NET MAUI apps: SDK-band workloads, JDK, Android SDK and emulators, a Windows development target, platform service registration, managed-phone debugging and Android CI builds. Use when setting up a MAUI machine in Visual Studio or VS Code, adding a platform target, wiring platform services, or when a MAUI build, workload or deployment fails.'
compatibility: 'Workstation bootstrap covers Windows with Visual Studio 2026 or VS Code. Android builds also run on Linux and macOS; the Windows target builds only on Windows.'
---

# .NET MAUI

Set up a workstation, choose where to debug and keep platform code behind platform-neutral
contracts, so most development happens without a phone. Verify current tooling versions while
working; MAUI, Android and workload guidance changes with each .NET release.

## Authorities

- [C# instructions](../../instructions/dotnet.csharp.instructions.md) own types, DI, cancellation,
  time and logging. [.NET instructions](../../instructions/dotnet.instructions.md) own solution,
  SDK and target-framework structure.
- [Configuration instructions](../../instructions/dotnet.configuration.instructions.md) own options
  binding and secrets. [Testing instructions](../../instructions/dotnet.testing.instructions.md) and
  the [test platform skill](../dotnet-test-platform/SKILL.md) own test projects and approval.
- [Dependency injection](../dotnet-dependency-injection/SKILL.md) owns lifetimes and optional
  dependencies. [GitHub Actions workflows](../github-actions-workflows/SKILL.md) owns the shared
  Android build workflow.
- The application repository's own instructions own its product platforms, application ID, minimum
  API level, permissions and privacy rules.

## Workflow

### 1. Establish the Context

From the repository root, record `dotnet --version`, `global.json`, `dotnet workload list`, every
project's `TargetFramework(s)`, the CI build command and the repository's platform rules. The SDK
selected by `global.json` decides which workload band must be installed.

### 2. Bootstrap the Workstation

Follow the [workstation bootstrap](references/workstation-bootstrap.md): .NET SDK, workloads,
JDK, Android SDK, emulator, then Visual Studio 2026 or VS Code, then verification. Ask before
installing anything that needs elevation or large downloads.

### 3. Choose Where to Debug

| Target | Use it for | Cannot show |
| --- | --- | --- |
| Windows development target | Services, UI layout, storage and network clients; fastest loop | Android APIs, permissions, background limits |
| Android emulator | Android APIs, runtime permissions, media providers, lifecycle | Vendor behavior, real camera output, performance |
| Physical phone | Final device validation | Nothing, but it costs the most setup |

Move to Android only when the change depends on Android behavior. On a phone managed by mobile
device management, enabling developer options, USB debugging or wireless debugging can mark it
non-compliant and block work apps; wireless debugging uses the same debugging service as USB, so a
policy covering one covers both. Prefer the emulator there. A spare phone helps only when it runs
the app's minimum API level; wireless pairing without a cable needs Android 11 or later.

### 4. Add a Windows Development Target

Use Windows as a development-only target when Android is the product platform:

```xml
<TargetFrameworks>net10.0-android</TargetFrameworks>
<TargetFrameworks Condition="$([MSBuild]::IsOSPlatform('windows'))">$(TargetFrameworks);net10.0-windows10.0.19041.0</TargetFrameworks>
<SupportedOSPlatformVersion Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)')) == 'windows'">10.0.17763.0</SupportedOSPlatformVersion>
<TargetPlatformMinVersion Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)')) == 'windows'">10.0.17763.0</TargetPlatformMinVersion>
<WindowsPackageType>None</WindowsPackageType>
```

- Make every existing Android-only property conditional on the `android` platform identifier.
- Linux CI never sees the Windows framework. Keep CI build and publish steps passing
  `-f net10.0-android` explicitly.
- Copy `Platforms/Windows/App.xaml`, `App.xaml.cs` and `app.manifest` from a temporary
  `dotnet new maui` project, renaming its namespace, then delete the project. An unpackaged app
  needs no `Package.appxmanifest`.
- Add `Properties/launchSettings.json` with a `"Windows Machine": { "commandName": "Project" }`
  profile so Visual Studio starts the unpackaged executable.
- With SDK 10.0.4xx the Windows target built with only `maui-android` installed; install the
  `maui-windows` workload only if the build reports it missing.
- Update the repository's platform-scope instructions and READMEs in the same change.

### 5. Compose Platform Services

- Put contracts and platform-neutral services in a plain `net10.0` library, so they build and test
  without workloads. Name interfaces for a capability, such as a media source or upload destination.
- Register platform implementations from a per-platform partial: declare
  `static partial void AddPlatformServices(MauiAppBuilder builder);` in `MauiProgram.cs` and
  implement it in `Platforms/<Platform>/MauiProgram.<Platform>.cs`. Platforms without an
  implementation compile it away, with no `#if` blocks.
- Resolve pages from DI in `App.CreateWindow` and pass them into the `Shell` constructor rather than
  relying on `ShellContent` `DataTemplate` creation. A page may take a platform-only service as an
  optional parameter defaulting to `null` and hide the matching controls.
- Run discovery, hashing and I/O with `Task.Run`, report through a `Progress<T>` created on the UI
  thread, and own cancellation with a per-operation `CancellationTokenSource`.
- Event handlers are `async void`: catch every expected failure, including
  `OptionsValidationException`, and show an actionable message without paths or exception details.
- `AddOptionsWithValidateOnStart` still binds, but MAUI never starts a host, so validation runs at
  the first `.Value` read. Handle it at that use site.

### 6. Validate

Ask before building, testing or deploying. Then:

1. Build the whole solution from the repository root; on Windows this covers both targets.
2. Run the platform-neutral unit tests; they need no workload, device or emulator.
3. Start the Windows executable once and confirm the main window appears.
4. Deploy to the emulator with `dotnet build <app>.csproj -t:Run -f net10.0-android` or from the IDE.
5. Run the repository's lint hooks; files created by agent tooling on Windows may need CRLF
   converted to the `.editorconfig` line ending.

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| `NETSDK1147` names `maui-android` or `android` | The SDK selected by `global.json` has no workload; Visual Studio installs workloads only for its own band. From an elevated prompt in the repository root, run `dotnet workload install maui-android`, wait for `Successfully installed workload(s)`, then confirm with `dotnet workload list` |
| Workload packs exist but `dotnet workload list` is empty | The install ran under another SDK band or did not finish; rerun from the repository root |
| `sdkmanager` or `avdmanager` exits 1 with no output | Set `JAVA_HOME` to the installed JDK first |
| Emulator does not start or is very slow | Enable the Windows Hypervisor Platform optional feature, reboot, and use an `x86_64` system image |
| `-p:AndroidBuildApplicationPackage=false` still packages, or `AndroidKeyStore=false` still signs | Neither property disables packaging or signing. For a compile-only check, use `-t:"Compile;_ReadAndroidManifest"`; that target is internal, so revalidate after workload updates |
| Windows app starts with a blank or missing page | The page was not registered in DI or the shell did not receive it; check `App.CreateWindow` |

## Maintaining This Skill

- Each .NET major: recheck workload IDs, whether the Windows target still needs no `maui-windows`
  workload, template files, minimum Windows versions and the `-t:Run` deployment target.
- Recheck the JDK version recommended by the .NET for Android and MAUI installation pages, which
  have disagreed.
- Recheck the VS Code .NET MAUI extension commands and the Android emulator system image names.
