# Win11 Dev Host Full Readiness Rerun

Date: 2026-06-08

Host: `DESKTOP-02NDERS` over SSH as `jose@100.110.8.112`.

## Current Space

- C: ended at `57.1 GiB` free of `388.76 GiB`.
- D: ended at `1748.16 GiB` free of `9313.97 GiB`.
- `Ubuntu-22.04`, `Ubuntu-20.04`, and `docker-desktop` were stopped at the end
  of the run.
- The Android x86_64 AVD was created on D: at
  `D:\android-avd\HydraCam_API33_x86_64.avd`.

## Windows Native

- `flutter doctor -v` on Windows is green for Windows, Android, Chrome, Visual
  Studio, devices, and network resources. The remaining doctor issue is the
  intentionally pinned Flutter SDK showing `[user-branch]` / unknown source.
- `flutter analyze` passed on the D-drive checkout.
- A normal `flutter build windows --debug --no-pub` still fails because Flutter
  creates plugin symlink entries whose `windows` subdirectories are not usable
  from this SSH session.
- A direct CMake recovery did pass after materializing the plugin folders:
  `sport_cam_sync.exe` was built under
  `D:\src\work\hydracamv2\build\windows\x64\runner\Debug`.
- The Windows debug binary smoke-started and stayed running for 12 seconds
  before being stopped.

## WSL Linux

- `Ubuntu-22.04` has `226G` available inside the WSL filesystem.
- Flutter for Linux is `3.44.1` stable and the Linux desktop toolchain is green.
- `flutter build linux --debug` passed from `/mnt/d/src/work/hydracamv2`.
- The Linux binary launched under WSLg and exposed a Dart VM service, then the
  timed smoke run logged a `MissingPluginException` for
  `permission_handler` / `requestPermissions`. That is an app/plugin startup
  issue, not a Linux build-toolchain failure.

## Android x86_64 Emulator

- `system-images;android-33;google_apis;x86_64` was already installed.
- `emulator -accel-check` reported WHPX installed and usable.
- Created `HydraCam_API33_x86_64` with device `pixel_5`, tag/ABI
  `google_apis/x86_64`.
- The emulator booted as `emulator-5554`, product/model
  `sdk_gphone64_x86_64`, Android 13 / API 33.
- `flutter devices` detected it as `android-x64`.
- `flutter build apk --debug` started and Gradle stayed CPU-active, but no APK
  was produced within the validation window. The Gradle/emulator process tree
  was stopped and verified absent at the end of the run.

## Remaining WSL Trim Candidates

No extra WSL deletion was performed in this run.

- `Ubuntu-22.04`: the safe obvious candidate remains stale pip-unpack content
  under `/tmp` from the earlier inventory, plus smaller apt/editor/cache items.
  Do not remove `/home/jose/keob-nodes`.
- `Ubuntu-20.04`: large old-worker candidates remain under `/opt`,
  `/home/ubuntu/venv`, and `/home/vectorblanco`. The
  `/home/ubuntu/bin/keob-nodes` tree is protected because it is referenced by
  the old worker crontab and contains sensitive project material.

## Open Gaps

1. Normal Flutter Windows builds still need the plugin symlink issue fixed for
   a fully ready developer workflow. The direct CMake workaround proves the
   host can compile and launch the binary, but it is not the normal workflow.
2. Linux app startup needs a platform guard or Linux implementation path for
   permission handling.
3. Android emulator build/install/launch is not complete. The AVD boots and is
   detected, but `assembleDebug` needs a follow-up run with deeper Gradle
   diagnostics or more time.
4. The checkout on Windows is still based on a sparse/tar workaround because
   colon-containing evidence paths prevent a normal Windows Git checkout.
