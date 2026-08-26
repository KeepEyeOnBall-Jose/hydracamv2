# Win11 Development Host

Last reviewed: 2026-06-09 (content dated 2026-06-09).
Last refreshed: 2026-06-09.

This document records the current Windows host prepared for HydraCam
build/debug/test work. The latest maintenance evidence root is
`logs/verification-runs/20260609-0415-win11-android-studio-quail-e-drive-move/`.
The latest aborted desktop/emulator proof wrap-up is
`docs/control/win11-triple-platform-proof-wrapup-2026-06-09.md`. The original
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

SSH key auth works on port 22. After the 2026-06-08 reboot reset, password auth
was used once to restore `authorized_keys`; key auth was then verified again.

## Storage Snapshot

Current cleanup/moveout plan:
`docs/superpowers/plans/2026-06-07-win11-dev-host-storage-cleanup.md`.

2026-06-08 live SSH storage inventory after the WSL cleanup, readiness rerun,
and Android Studio cleanup:

| Drive | Volume | Filesystem | Free | Size | Notes |
| --- | --- | --- | ---: | ---: | --- |
| `C:` | | NTFS | 70.57 GiB | 388.76 GiB | No longer the immediate Android/Gradle blocker, but keep WSL/Docker/SDK moveouts on the plan to avoid recurrence. |
| `D:` | `Elements` | NTFS | 1749.15 GiB | 9313.97 GiB | Preferred moveout target for dev roots, caches, WSL, Docker data, and the Android AVD home. |
| `E:` | `80GB-workenv` | NTFS | about 24.2 GiB after the HydraCam move | 86.84 GiB | SSD workenv partition; now hosts `E:\work-repos\hydracamv2`. Keep SDKs and bulk caches off this smaller partition. |
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
| Android Studio | Working install is `C:\Users\jose\AppData\Local\Programs\Android Studio Fixed`, Quail `2026.1.1.8`, `AndroidStudio2026.1.1`, build `AI-261.23567.138.2611.15503007`. On 2026-06-09 the stale Windows uninstall/winget version was repaired after the actual product files were confirmed current. Earlier 2026-06-08 cleanup removed stale Program Files installs and old config/cache trees. |
| Git | `2.45.1.windows.1`. |
| PowerShell | PowerShell 7 `7.5.5` present. |
| VS Code | Microsoft Visual Studio Code User `1.110.0` is installed according to winget; `code` on PATH resolves to a Cursor-style `0.45.14` command. |
| Visual Studio | Visual Studio Community 2022 `17.14.27` with Windows desktop workload; Flutter doctor sees Windows SDK `10.0.26100.0`. |
| Java | Android Studio Fixed JBR `21.0.10` is used by Flutter/Android Studio. A user-local Temurin JDK 17 is also installed at `C:\src\jdk-17`, with `JAVA17_HOME=C:\src\jdk-17`, version `17.0.19`. |
| Android SDK | `C:\Users\jose\AppData\Local\Android\Sdk`; platform `android-36`, build-tools `36.1.0`, command-line tools `sdkmanager` `20.0`, platform-tools `37.0.0`, emulator `36.6.11`, and NDK `28.2.13676358`. |
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
  `/home/jose/keob-nodes` as protected. The final readiness run reports
  `226G` available inside the WSL filesystem.
- `Ubuntu-20.04` remains an old-worker candidate. The large non-cache areas are
  `/opt`, `/home/ubuntu/venv`, and `/home/vectorblanco`; keep
  `/home/ubuntu/bin/keob-nodes` protected until the old worker crontab,
  credentials, and project material are explicitly retired or archived.
- The readiness rerun ended with no emulator, Java, Dart, or HydraCam process
  left running; only `adb` remained.

## Checkouts

Primary Windows checkout:

- `E:\work-repos\hydracamv2`
- Current primary working checkout on the SSD workenv partition.
- `flutter pub get` and `flutter doctor -v` passed from this path on
  2026-06-09 after the Android Studio/SDK repair.

Compatibility junction:

- `D:\src\work\hydracamv2`
- Junction to `E:\work-repos\hydracamv2` for older scripts and evidence
  harnesses.

Historical C: checkout:

- `C:\Users\jose\src\work\hydracamv2`
- Sparse checkout from GitHub commit
  `29e05995df040df5904f3c18bc25c7776cc38733`.
- Full Windows Git checkout fails because the repository contains log paths
  with colons, for example an ADB host path under
  `logs/verification-runs/.../192.168.178.64:5555/...`.

D-drive workaround checkout before 2026-06-09:

- `D:\src\work\hydracamv2`
- Originally extracted from the same sparse tarball when C: had no free space;
  it was moved to `E:\work-repos\hydracamv2` on 2026-06-09.
- During the 2026-06-08 readiness rerun, current local source was synced into
  this checkout by tarball. Its `git rev-parse HEAD` still reports the older
  sparse checkout commit `29e05995df040df5904f3c18bc25c7776cc38733`, so use
  the validation logs rather than remote Git status as the source-sync proof.
- `flutter pub get` passed there with `GRADLE_USER_HOME`, `PUB_CACHE`, `TEMP`,
  and `TMP` redirected to D:.

## Validation Results

| Check | Result |
| --- | --- |
| SSH identity | Passed: `hostname`, `whoami`, and Windows version returned over SSH. |
| `flutter doctor -v` on Windows | Passed except for the expected pinned SDK warning: Windows, Android toolchain, Chrome, Visual Studio, connected desktop/web devices, and network resources are green. Only Flutter's `[user-branch]`/unknown-source warning remains. |
| Android Studio IDE | Passed by process/log smoke on 2026-06-08: `C:\Users\jose\AppData\Local\Programs\Android Studio Fixed\bin\studio64.exe D:\src\work\hydracamv2` stayed alive during the 45-second check, updated `AndroidStudio2025.3.3\log\idea.log`, accepted the HydraCam project path, and produced zero lines matching the prior `Start Failed`, duplicate registration, `PluginException`, `SEVERE`, or internal-error crash signatures. `flutter doctor -v` now resolves Java from this fixed install. A follow-up interactive scheduled task launched the fixed IDE for the active RDP session as PID `2972`; the task and temporary wrapper were deleted after launch. |
| `flutter pub get` on Windows C: checkout | Passed. |
| `flutter analyze` on Windows D: checkout | Passed: no issues found on 2026-06-08. |
| `flutter test` on Windows C: checkout | Failed: `+87 ~1 -3`; failing tests were `test/platform/multi_device_orchestration_test.dart` scenario P1, plus `tearDownAll` failures in `permission_service_test.dart` and `session_manager_test.dart`. |
| `flutter build windows --debug` | Passed on the D: checkout in `windows-native-build-final-pass.txt`; plugin symlinks were inspected read-only and the normal Flutter Windows debug build produced `sport_cam_sync.exe`. |
| Windows native binary | Passed on 2026-06-08: `sport_cam_sync.exe` built under `D:\src\work\hydracamv2\build\windows\x64\runner\Debug`, smoke-started, stayed alive for 10 seconds, and was stopped cleanly. |
| `flutter build apk --debug` on C: checkout | Failed after about 10 minutes because C: is full: Gradle reported `Espacio en disco insuficiente` while extracting Flutter JNI artifacts. |
| `flutter build apk --debug --target-platform android-x64` on D: checkout | Passed in `android-x86-emulator-x64-after-windows-pubget.txt` after regenerating Windows-side `.dart_tool` metadata with `flutter clean` and `flutter pub get`. |
| `flutter doctor -v` in WSL | Partial: Linux desktop toolchain is green and Flutter is `3.44.1`; Android SDK and Chrome are not configured inside WSL. |
| `flutter build linux --debug` in WSL | Passed on 2026-06-08 from `/mnt/d/src/work/hydracamv2`. Output: `build/linux/x64/debug/bundle/sport_cam_sync`. The binary launched under WSLg, exposed a Dart VM service, and ran until the intentional 12-second timeout with no `MissingPluginException`, `RenderFlex`, uncaught zone error, or socket exception in the final log scan. |
| Android x86_64 emulator | Passed: `HydraCam_API33_x86_64` was created on D:, booted with WHPX, and `flutter devices` saw it as `android-x64` / Android 13 API 33. The x64 APK built, `adb install -r` returned `Success`, and monkey launched `com.amaia23.hydracam/.MainActivity`; logcat shows the app process start. |
| `adb devices -l` | No Android phones attached during inventory. |
| `flutter devices` on Windows | Windows desktop, Chrome, and Edge only; no phone was visible. |
| Windows camera inventory | DirectShow sees `USB2.0 HD UVC WebCam`, `DroidCam Video`, and `OBS Virtual Camera`; PnP also reports `Camera DFU Device`. |
| WSL USB/camera inventory | `lsusb` and `v4l2-ctl` are installed, but no `/dev/video0` is present. USB camera forwarding to WSL needs `usbipd-win`. |

## Remaining Gaps

1. Keep C: from regressing. It is no longer full, but WSL, Docker, Android SDK,
   and cache moveouts should still be completed through supported tools.
2. From the active RDP session, confirm the launched Android Studio window is
   visible, then run one IDE-side emulator/build smoke against
   `D:\src\work\hydracamv2`.
3. Keep using the D: tar/sync checkout until colon-containing evidence paths are
   removed or renamed enough for normal Windows Git operations.
4. Install `usbipd-win` from an elevated/admin Windows session before WSL USB
   camera attach tests can run.
5. Remove or rename colon-containing evidence paths in Git if normal Windows
   clones are expected.
6. Attach supported Android API 24+ phones and rerun `adb devices -l`,
   `flutter devices`, and one `flutter run -d <serial>` smoke.
7. Resolve the three failing Flutter tests before treating the Win11 host as a
   green CI-grade validator.
8. Decide whether the PATH `code` command should point to Microsoft VS Code or
   whether the current Cursor-style command is acceptable.
