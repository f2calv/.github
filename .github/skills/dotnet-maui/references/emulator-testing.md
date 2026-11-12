# Emulator Testing

How to exercise an Android app on the Windows emulator when it signs in, calls a private endpoint
or records audio. Run every command from a terminal where `adb` resolves, usually
`<sdk>\platform-tools\adb.exe`.

## Contents

- [Launch](#launch)
- [Private Endpoints](#private-endpoints)
- [Microphone](#microphone)
- [Deploy and Inspect](#deploy-and-inspect)

## Launch

```powershell
emulator -avd <avd> -memory 4096 -no-boot-anim -dns-server '<vpn-dns>,1.1.1.1' -allow-host-audio
adb shell getprop sys.boot_completed   # 1 when booted
```

- Check acceleration with `emulator -accel-check`; WHPX must be usable.
- `-memory` overrides an AVD saved with too little RAM without editing `config.ini`.
- Restart to change launch options: `adb emu kill`, wait for the `qemu-system-x86_64` process to
  exit, then launch again. Starting a new emulator before the old one has exited fails silently.
- Leave the emulator running only while testing; stop it with `adb emu kill` afterwards.

## Private Endpoints

- With no `-dns-server` the emulator may resolve nothing. Pass the DNS server of the interface that
  resolves the private names (for example a VPN adapter, from `Get-DnsClientServerAddress`) first,
  then a public resolver. Check with `adb shell ping -c 1 <host>`: a resolved address is enough even
  when ICMP gets no reply.
- Install a private root certificate as a user CA: `adb push <ca>.crt /sdcard/Download/`, open
  **Settings → Security & privacy → More security settings → Encryption & credentials → Install a
  certificate → CA certificate** (`adb shell am start -a android.settings.SECURITY_SETTINGS` gets
  close), and pick the file. The app must trust user anchors in its network security configuration.
- The first browser sign-in shows Chrome's first-run screen; choose to continue without an account.

## Microphone

The emulator sends silence unless both are set:

1. launch with `-allow-host-audio`;
2. run `adb emu avd hostmicon` after boot.

Windows must also allow desktop apps to use the microphone. To tell an app fault from a silent
input, check `adb shell dumpsys audio`: `rec start ... not silenced` for the package means Android is
recording, and `App op 27 missing, silencing record` while the app is in the background is normal.
`adb shell appops get <package> RECORD_AUDIO` shows the permission state.

## Deploy and Inspect

| Task | Command |
| --- | --- |
| Build, install and start a Debug build | `dotnet build <app>.csproj -t:Run -f net10.0-android` |
| Start an installed app | `adb shell monkey -p <package> -c android.intent.category.LAUNCHER 1` |
| Read a crash | `adb logcat -d -s AndroidRuntime:E`; the `FATAL EXCEPTION` line names the .NET exception |
| Clear the log before reproducing | `adb logcat -c` |
| Screenshot | `adb exec-out screencap -p > <file>.png` |
| Read a Debug app's preferences | `adb exec-out run-as <package> cat shared_prefs/<package>_preferences.xml`; mask values before sharing |
| Tap a control by its text | `adb shell uiautomator dump /sdcard/ui.xml`, read `bounds` for the node, then `adb shell input tap <x> <y>` |

`run-as` works only for debuggable builds. Never print preference values that hold identifiers into
logs or reports.
