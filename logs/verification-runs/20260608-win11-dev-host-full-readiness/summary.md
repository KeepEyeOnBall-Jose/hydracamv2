# Win11 Dev Host Full Readiness Rerun

Date: 2026-06-08

Host: `DESKTOP-02NDERS` over SSH as `jose@100.110.8.112`.

## Current Space

- Final live state: C: `60.95 GiB` free of `388.76 GiB`; D:
  `1749.15 GiB` free of `9313.97 GiB`.
- WSL `Ubuntu-22.04` internal filesystem: `226G` available at `/`.
- No emulator, Java, Dart, or app process was left running; only `adb` remained.
- The Android x86_64 AVD is on D: at
  `D:\android-avd\HydraCam_API33_x86_64.avd`.

## Windows Native

- `flutter doctor -v` is green for Windows, Android, Chrome, Visual Studio,
  devices, and network resources. The only doctor warning remains the pinned
  Flutter SDK showing `[user-branch]` / unknown source.
- `flutter analyze` passed on the D-drive checkout.
- `flutter build windows --debug --no-pub` passed.
- `sport_cam_sync.exe` was built at
  `D:\src\work\hydracamv2\build\windows\x64\runner\Debug\sport_cam_sync.exe`.
- The Windows debug binary smoke-started, stayed alive for 10 seconds, and was
  stopped cleanly.

## WSL Linux

- `Ubuntu-22.04` has Flutter `3.44.1` stable and `226G` available inside WSL.
- `flutter build linux --debug` passed from `/mnt/d/src/work/hydracamv2`.
- The Linux binary launched under WSLg, exposed a Dart VM service, and ran until
  the intentional 12-second timeout.
- Final log scan found no `MissingPluginException`, `RenderFlex`,
  `Uncaught zone error`, or `SocketException`.
- WSL-specific DBus-dependent plugin paths are now guarded: permission startup,
  connectivity stream/checks, network-info calls, battery monitoring, and
  wakelock startup.

## Android x86_64 Emulator

- `system-images;android-33;google_apis;x86_64` is installed.
- `emulator -accel-check` reported WHPX installed and usable.
- `HydraCam_API33_x86_64` boots as `sdk_gphone64_x86_64`, Android 13 / API 33.
- `flutter devices` detected it as `android-x64`.
- `flutter build apk --debug --target-platform android-x64` passed.
- `adb install -r` returned `Success`.
- `monkey -p com.amaia23.hydracam -c android.intent.category.LAUNCHER 1`
  launched `com.amaia23.hydracam/.MainActivity`; logcat shows app process start.

## Remaining WSL Trim Candidates

No extra WSL deletion was performed in this readiness rerun.

- `Ubuntu-22.04`: the safe obvious candidate remains stale pip-unpack content
  under `/tmp` from the earlier inventory, plus smaller apt/editor/cache items.
  Do not remove `/home/jose/keob-nodes`.
- `Ubuntu-20.04`: large old-worker candidates remain under `/opt`,
  `/home/ubuntu/venv`, and `/home/vectorblanco`. The
  `/home/ubuntu/bin/keob-nodes` tree is protected because it is referenced by
  the old worker crontab and contains sensitive project material.

## Open Gaps

1. C: has enough room now, but WSL/Docker/SDK/cache moveouts should still be
   completed through supported tools to avoid recurrence.
2. Windows Git checkout remains constrained by colon-containing evidence paths;
   the D: tar/sync checkout is the practical build target.
3. The pinned Flutter SDK still reports `[user-branch]` / unknown source in
   `flutter doctor`; this is expected for the pinned SDK, not a build blocker.
4. `usbipd-win` is still missing and requires elevated/admin installation
   before WSL USB camera attach testing.
5. No physical Android phones were attached during this run.
