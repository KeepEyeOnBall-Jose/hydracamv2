# Win11 Development Host

Last refreshed: 2026-06-07.

This document records the current Windows host prepared for HydraCam
build/debug/test work. The evidence root for this pass is
`logs/verification-runs/20260607-1715-win11-dev-host-readiness/`.

## Host Identity

| Field | Value |
| --- | --- |
| Hostname | `DESKTOP-02NDERS` |
| Tailscale IP | `100.110.8.112` |
| LAN IP | `192.168.178.128` |
| MagicDNS | `desktop-02nders.tail6ce139.ts.net` |
| SSH user | `jose` |
| SSH key used from Mac | `/Users/jose/Downloads/codex_ssh_key` |
| Windows version | Windows 11 Pro 25H2, build `10.0.26200.8457` |

SSH key auth works on port 22. Password auth was not needed for this setup run.

## Storage Snapshot

Current cleanup/moveout plan:
`docs/superpowers/plans/2026-06-07-win11-dev-host-storage-cleanup.md`.

2026-06-07 live SSH storage inventory:

| Drive | Volume | Filesystem | Free | Size | Notes |
| --- | --- | --- | ---: | ---: | --- |
| `C:` | | NTFS | 0.14 GiB | 388.76 GiB | Effectively full; blocks Android/Gradle work. |
| `D:` | `Elements` | NTFS | 1755.69 GiB | 9313.97 GiB | Preferred moveout target for dev roots, caches, WSL, and Docker data. |
| `E:` | `80GB-workenv` | NTFS | 26.25 GiB | 86.84 GiB | Small workenv partition; not preferred for large SDKs. |
| `F:` | `Maxtor` | NTFS | 1552.36 GiB | 3725.90 GiB | Archive-capable partition. |
| `G:` | `Elements SE` | NTFS | 2018.60 GiB | 3725.99 GiB | Archive-capable partition. |
| `I:` | `SEAGATE4TB` | exFAT | 3580.99 GiB | 3725.82 GiB | Archive-capable removable/exFAT target. |

High-value C: moveout candidates from the same inventory include the WSL Ubuntu
22.04 VHD (`22.18 GiB`), Android SDK system images (`13.81 GiB`), Docker WSL
data (`7.82 GiB`), `C:\src` (`6.93 GiB`), Downloads (`3.98 GiB`), a PyCharm
heap dump (`3.21 GiB`), Gradle/Pub caches, and the sparse C: HydraCam checkout
(`1.05 GiB`). Move WSL and Docker through their supported tools/settings; do
not manually move raw VHD files.

## Installed Toolchain

| Area | Current state |
| --- | --- |
| Flutter for Windows | `C:\src\flutter`, Flutter `3.44.1`, Dart `3.12.1`, revision `924134a44c`. `flutter doctor` reports channel `[user-branch]` / unknown source because the SDK is pinned directly, but the framework revision matches the requested version. |
| Flutter for WSL | `/home/jose/development/flutter`, Flutter `3.44.1`, Dart `3.12.1`, stable channel. |
| Git | `2.45.1.windows.1`. |
| PowerShell | PowerShell 7 `7.5.5` present. |
| VS Code | Microsoft Visual Studio Code User `1.110.0` is installed according to winget; `code` on PATH resolves to a Cursor-style `0.45.14` command. |
| Visual Studio | Visual Studio Community 2022 `17.14.27` with Windows desktop workload; Flutter doctor sees Windows SDK `10.0.26100.0`. |
| Java | Android Studio JBR `21.0.10` is used by Flutter/Android Studio. A user-local Temurin JDK 17 is also installed at `C:\src\jdk-17`, with `JAVA17_HOME=C:\src\jdk-17`, version `17.0.19`. |
| Android SDK | `C:\Users\jose\AppData\Local\Android\Sdk`; platform `android-36`, build-tools `35.0.0`, NDK `28.2.13676358`, platform-tools `37.0.0`, emulator `36.6.11`. The build also installed platform/build tools for Android 34/35 and CMake `3.22.1`. |
| Android licenses | Accepted after the setup run. |
| FFmpeg | Present and can list DirectShow devices. |
| WSL | `Ubuntu-22.04` is WSL2 and is now the default distro. Linux desktop deps, GStreamer dev packages, `usbutils`, `v4l-utils`, `ripgrep`, and `mesa-utils` are installed. |
| usbipd-win | Missing. Install requires an elevated/admin Windows session. |

Reference setup docs used for expected tool categories:
[Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup),
[Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup),
[Android OEM USB drivers](https://developer.android.com/studio/run/oem-usb),
and [Microsoft WSL USB/IP](https://learn.microsoft.com/en-us/windows/wsl/connect-usb).

## WSL Worker/Garbage Snapshot

2026-06-08 read-only inventory:
`logs/verification-runs/20260608-win11-wsl-worker-garbage-inventory/`.

- `Ubuntu-20.04` is still present as WSL1 and stopped after inspection. It has
  a historical KEOB worker setup: user `ubuntu` has an `@reboot` crontab for
  `/home/ubuntu/bin/keob-nodes/queue-poller/queue-poller.py`, logging to
  `/var/log/keob/queue-poller.log`. `/var/tmp` and `/tmp` are empty, and
  `/var/log/keob` is only about `26M`; the large payloads are old project,
  model, venv, and IDE directories: `/opt` about `9.9G`, `/home/ubuntu/venv`
  about `6.3G`, `/home/ubuntu/bin/keob-nodes` about `2.4G`, and
  `/home/vectorblanco` about `6.1G`.
- `Ubuntu-22.04` is the default WSL2 distro and was stopped after inspection.
  Its Windows VHD was `22.18 GiB` before this pass. `/var/tmp` and `/var/log`
  are tiny, but `/tmp` contains about `3.5G` of stale pip unpack files. Other
  large candidates are `/home/jose/borrame` about `4.5G`, `/home/jose/.cache`
  about `3.2G`, `/home/jose/keob-nodes` about `2.1G`, and
  `/home/jose/.local/share/mamba` about `1.9G`.
- Treat `keob-nodes` trees as sensitive because the inventory saw credential
  and SSH-key paths. Archive or review credentials before deleting. For WSL2,
  deleting Linux files does not necessarily shrink the Windows VHD immediately;
  shut down and compact/export-import after cleanup if the target is C: free
  space.

2026-06-08 authorized cleanup:
`logs/verification-runs/20260608-win11-wsl-authorized-cache-cleanup/`.

- Deleted only the user-authorized `Ubuntu-22.04` targets:
  `/home/jose/borrame`, `/home/jose/.cache/pip`, and
  `/home/jose/.local/share/mamba/pkgs/cache`.
- Left `/home/jose/keob-nodes` present at about `2.1G`.
- `Ubuntu-22.04` internal filesystem usage dropped from `21G` used to `13G`
  used. Windows C: later reported `57.18 GiB` free, while the `Ubuntu-22.04`
  `ext4.vhdx` still reported `22.18 GiB`. Both Ubuntu distros and
  `docker-desktop` were left stopped.

## Checkouts

Primary Windows checkout:

- `C:\Users\jose\src\work\hydracamv2`
- Sparse checkout from GitHub commit
  `29e05995df040df5904f3c18bc25c7776cc38733`.
- Full Windows Git checkout fails because the repository contains log paths
  with colons, for example an ADB host path under
  `logs/verification-runs/.../192.168.178.64:5555/...`.

D-drive workaround checkout:

- `D:\src\work\hydracamv2`
- Extracted from the same sparse tarball because C: has no free space and
  Windows Git still touches invalid colon-named paths during sparse checkout.
- `flutter pub get` passed there with `GRADLE_USER_HOME`, `PUB_CACHE`, `TEMP`,
  and `TMP` redirected to D:.

## Validation Results

| Check | Result |
| --- | --- |
| SSH identity | Passed: `hostname`, `whoami`, and Windows version returned over SSH. |
| `flutter doctor -v` on Windows | Partial: Windows, Android toolchain, Chrome, Visual Studio, connected desktop/web devices, and network resources are green after license acceptance. Only Flutter's pinned `[user-branch]`/unknown-source warning remains. |
| `flutter pub get` on Windows C: checkout | Passed. |
| `flutter analyze` on Windows C: checkout | Passed: no issues found. |
| `flutter test` on Windows C: checkout | Failed: `+87 ~1 -3`; failing tests were `test/platform/multi_device_orchestration_test.dart` scenario P1, plus `tearDownAll` failures in `permission_service_test.dart` and `session_manager_test.dart`. |
| `flutter build windows --debug` | Blocked by Windows symlink privilege. A generic symlink test requires administrator privileges, and Flutter plugin symlinks under `windows\flutter\ephemeral\.plugin_symlinks` exist but their `windows` child directories are not accessible, so CMake cannot add plugin subdirectories. |
| `flutter build apk --debug` on C: checkout | Failed after about 10 minutes because C: is full: Gradle reported `Espacio en disco insuficiente` while extracting Flutter JNI artifacts. |
| `flutter build apk --debug` on D: checkout | Not passed. The D: tarball checkout and `pub get` passed, but the Gradle build did not produce an APK before the stalled attempt was stopped. |
| `flutter doctor -v` in WSL | Partial: Linux desktop toolchain is green and Flutter is `3.44.1`; Android SDK and Chrome are not configured inside WSL. |
| `flutter build linux --debug` in WSL | Passed after installing GStreamer development packages and cleaning stale Linux CMake artifacts. Output: `build/linux/x64/debug/bundle/sport_cam_sync`. |
| `adb devices -l` | No Android phones attached during inventory. |
| `flutter devices` on Windows | Windows desktop, Chrome, and Edge only; no phone was visible. |
| Windows camera inventory | DirectShow sees `USB2.0 HD UVC WebCam`, `DroidCam Video`, and `OBS Virtual Camera`; PnP also reports `Camera DFU Device`. |
| WSL USB/camera inventory | `lsusb` and `v4l2-ctl` are installed, but no `/dev/video0` is present. USB camera forwarding to WSL needs `usbipd-win`. |

## Remaining Gaps

1. Free C: disk space. A later cleanup inventory reported only `0.14 GiB` free.
   This blocks normal Android/Gradle work and likely future SDK updates. Use
   `docs/superpowers/plans/2026-06-07-win11-dev-host-storage-cleanup.md`.
2. Enable Windows symlink privilege, either through Developer Mode or an
   elevated/admin build session. Native Windows Flutter plugin symlinks are not
   usable from the current SSH session.
3. Install `usbipd-win` from an elevated/admin Windows session before WSL USB
   camera attach tests can run.
4. Remove or rename colon-containing evidence paths in Git if normal Windows
   clones are expected.
5. Attach supported Android API 24+ phones and rerun `adb devices -l`,
   `flutter devices`, and one `flutter run -d <serial>` smoke.
6. Resolve the three failing Flutter tests before treating the Win11 host as a
   green CI-grade validator.
7. Decide whether the PATH `code` command should point to Microsoft VS Code or
   whether the current Cursor-style command is acceptable.
