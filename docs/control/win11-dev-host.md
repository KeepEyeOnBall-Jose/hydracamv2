# Win11 Development Host

Last refreshed: 2026-06-08.

This document records the current Windows host prepared for HydraCam
build/debug/test work. The latest evidence root is
`logs/verification-runs/20260608-win11-dev-host-full-readiness/`. The original
setup evidence root is
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

2026-06-08 live SSH storage inventory after the WSL cleanup and readiness
rerun:

| Drive | Volume | Filesystem | Free | Size | Notes |
| --- | --- | --- | ---: | ---: | --- |
| `C:` | | NTFS | 57.10 GiB | 388.76 GiB | No longer the immediate Android/Gradle blocker, but keep WSL/Docker/SDK moveouts on the plan to avoid recurrence. |
| `D:` | `Elements` | NTFS | 1748.16 GiB | 9313.97 GiB | Preferred moveout target for dev roots, caches, WSL, Docker data, and the Android AVD home. |
| `E:` | `80GB-workenv` | NTFS | 25.53 GiB | 86.84 GiB | Small workenv partition; not preferred for large SDKs. |
| `F:` | `Maxtor` | NTFS | 1552.36 GiB | 3725.90 GiB | Archive-capable partition. |
| `G:` | `Elements SE` | NTFS | 2018.60 GiB | 3725.99 GiB | Archive-capable partition. |
| `I:` | `SEAGATE4TB` | exFAT | 3580.99 GiB | 3725.82 GiB | Archive-capable removable/exFAT target. |

High-value long-term C: moveout candidates still include the WSL Ubuntu 22.04
VHD, Android SDK system images, Docker WSL data, `C:\src`, Downloads, Gradle/Pub
caches, and the sparse C: HydraCam checkout. Move WSL and Docker through their
supported tools/settings; do not manually move raw VHD files.

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
| Android AVD | `HydraCam_API33_x86_64` created under `D:\android-avd`; target Google APIs Android 13 / API 33, ABI `x86_64`, device `pixel_5`. WHPX acceleration is usable. |
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

2026-06-08 readiness rerun:
`logs/verification-runs/20260608-win11-dev-host-full-readiness/`.

- No additional WSL deletion was performed during the readiness rerun.
- `Ubuntu-22.04` still has the safest obvious trim candidate in stale
  `/tmp` pip-unpack content from the earlier inventory. Treat
  `/home/jose/keob-nodes` as protected.
- `Ubuntu-20.04` remains an old-worker candidate. The large non-cache areas are
  `/opt`, `/home/ubuntu/venv`, and `/home/vectorblanco`; keep
  `/home/ubuntu/bin/keob-nodes` protected until the old worker crontab,
  credentials, and project material are explicitly retired or archived.
- The readiness rerun ended with `Ubuntu-22.04`, `Ubuntu-20.04`, and
  `docker-desktop` stopped.

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
- Originally extracted from the same sparse tarball when C: had no free space;
  it remains the preferred working checkout because Windows Git still touches
  invalid colon-named paths during sparse checkout.
- `flutter pub get` passed there with `GRADLE_USER_HOME`, `PUB_CACHE`, `TEMP`,
  and `TMP` redirected to D:.

## Validation Results

| Check | Result |
| --- | --- |
| SSH identity | Passed: `hostname`, `whoami`, and Windows version returned over SSH. |
| `flutter doctor -v` on Windows | Partial: Windows, Android toolchain, Chrome, Visual Studio, connected desktop/web devices, and network resources are green. Only Flutter's pinned `[user-branch]`/unknown-source warning remains. |
| `flutter pub get` on Windows C: checkout | Passed. |
| `flutter analyze` on Windows D: checkout | Passed: no issues found on 2026-06-08. |
| `flutter test` on Windows C: checkout | Failed: `+87 ~1 -3`; failing tests were `test/platform/multi_device_orchestration_test.dart` scenario P1, plus `tearDownAll` failures in `permission_service_test.dart` and `session_manager_test.dart`. |
| `flutter build windows --debug` | Normal Flutter path still blocked: plugin symlink entries under `windows\flutter\ephemeral\.plugin_symlinks` exist, but their `windows` child directories are not usable, so CMake cannot add plugin subdirectories. A corrected generic PowerShell symlink test still requires administrator privileges from the SSH session even though Developer Mode registry flags are set. |
| Windows native binary | Passed with a workaround on 2026-06-08: after materializing plugin folders and invoking CMake/MSBuild directly, `sport_cam_sync.exe` built under `D:\src\work\hydracamv2\build\windows\x64\runner\Debug` and smoke-started for 12 seconds before being stopped. This proves the host can compile and launch the native binary, but the normal Flutter build workflow is not green. |
| `flutter build apk --debug` on C: checkout | Failed after about 10 minutes because C: is full: Gradle reported `Espacio en disco insuficiente` while extracting Flutter JNI artifacts. |
| `flutter build apk --debug` on D: checkout | Not passed. The D: tarball checkout and `pub get` passed, but the Gradle build did not produce an APK before the stalled attempt was stopped. |
| `flutter doctor -v` in WSL | Partial: Linux desktop toolchain is green and Flutter is `3.44.1`; Android SDK and Chrome are not configured inside WSL. |
| `flutter build linux --debug` in WSL | Passed again on 2026-06-08 from `/mnt/d/src/work/hydracamv2`. Output: `build/linux/x64/debug/bundle/sport_cam_sync`. The binary launched under WSLg and exposed a Dart VM service, then logged a `MissingPluginException` for `permission_handler` / `requestPermissions` during startup before the timed smoke run ended. |
| Android x86_64 emulator | Partial: `HydraCam_API33_x86_64` was created on D:, booted with WHPX, and `flutter devices` saw it as `android-x64` / Android 13 API 33. `flutter build apk --debug` stayed CPU-active but did not produce an APK inside the validation window; the Gradle/emulator process tree was stopped and verified absent. |
| `adb devices -l` | No Android phones attached during inventory. |
| `flutter devices` on Windows | Windows desktop, Chrome, and Edge only; no phone was visible. |
| Windows camera inventory | DirectShow sees `USB2.0 HD UVC WebCam`, `DroidCam Video`, and `OBS Virtual Camera`; PnP also reports `Camera DFU Device`. |
| WSL USB/camera inventory | `lsusb` and `v4l2-ctl` are installed, but no `/dev/video0` is present. USB camera forwarding to WSL needs `usbipd-win`. |

## Remaining Gaps

1. Keep C: from regressing. It is no longer full, but WSL, Docker, Android SDK,
   and cache moveouts should still be completed through supported tools.
2. Fix Windows symlink privilege or Flutter plugin-link handling. The direct
   CMake workaround can build a binary, but normal `flutter build windows` is
   still not a ready daily workflow from SSH.
3. Finish the Android emulator lane. The x86_64 AVD boots and is detected; the
   remaining gap is `assembleDebug`/install/launch completion with deeper Gradle
   diagnostics or a longer controlled build window.
4. Add or guard Linux permission handling. The Linux binary launches, but app
   startup currently logs `MissingPluginException` for `requestPermissions`.
5. Install `usbipd-win` from an elevated/admin Windows session before WSL USB
   camera attach tests can run.
6. Remove or rename colon-containing evidence paths in Git if normal Windows
   clones are expected.
7. Attach supported Android API 24+ phones and rerun `adb devices -l`,
   `flutter devices`, and one `flutter run -d <serial>` smoke.
8. Resolve the three failing Flutter tests before treating the Win11 host as a
   green CI-grade validator.
9. Decide whether the PATH `code` command should point to Microsoft VS Code or
   whether the current Cursor-style command is acceptable.
