# Evidence Run: Prepare Win11 HydraCam development host

- Source: user-request: Win11 HydraCam Host Setup Execution Plan
- Slug: `win11-dev-host-readiness`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [x] Win11 is reachable over SSH and reports host identity.
- [x] Windows native Flutter and Android build tooling is installed or has explicit blockers.
- [x] HydraCam checkout exists on Win11 and Windows/Android validation gates are run.
- [x] WSL/Linux lane is installed and validated for Linux desktop build.
- [x] Phone and USB camera inventory is captured without reopening desktop capture scope.

## Device Matrix

| Device | Runtime | Identifier | Role |
| --- | --- | --- | --- |
| DESKTOP-02NDERS | Windows 11 Pro 25H2 build `10.0.26200.8457` | Tailscale `100.110.8.112`, LAN `192.168.178.128` | build/debug/test host |
| Ubuntu-22.04 | WSL2, Ubuntu 22.04.1 LTS | default WSL distro | Linux desktop build lane |
| USB2.0 HD UVC WebCam | Windows DirectShow camera | `USB\VID_13D3&PID_56A2&MI_00...` | USB camera inventory only |
| DroidCam Video | Windows DirectShow virtual camera | `ROOT\MEDIA\0001` | camera inventory only |
| OBS Virtual Camera | Windows DirectShow virtual camera | software device | camera inventory only |

## Evidence

- SSH identity, toolchain install/repair, Windows Flutter doctor, analyzer,
  tests, Windows build diagnostic, Android build attempts, WSL setup/build, USB
  camera inventory, and disk-space snapshots are in `commands.log`.
- Scripts used for repeatable remote setup/validation are saved in this run
  directory as `win11-*.ps1` and `win11-*.sh`.
- Windows `flutter doctor -v` after license acceptance has one remaining issue:
  the pinned Flutter SDK reports channel `[user-branch]` / unknown source.
- Windows `flutter analyze` passed with no issues.
- Windows `flutter test` failed three tests:
  `test/platform/multi_device_orchestration_test.dart` scenario P1, plus
  `tearDownAll` failures in `permission_service_test.dart` and
  `session_manager_test.dart`.
- Windows native build is blocked by symlink privilege: generic symlink creation
  requires admin, and Flutter plugin links exist but their `windows` child paths
  do not resolve for CMake.
- Android SDK and licenses are installed, but the C: checkout APK build failed
  because C: has `0` bytes free. A D: tarball checkout and `pub get` passed,
  but the D: Gradle build did not produce an APK before the stalled attempt was
  stopped.
- WSL Ubuntu 22.04 has Flutter `3.44.1`, Dart `3.12.1`, Linux desktop deps,
  GStreamer dev deps, `usbutils`, `v4l-utils`, `ripgrep`, and `mesa-utils`.
  `flutter build linux --debug` passed after cleaning stale Linux CMake
  artifacts; output was `build/linux/x64/debug/bundle/sport_cam_sync`.
- No Android phones were attached. Windows saw desktop/web Flutter targets only.
- Windows camera inventory found `USB2.0 HD UVC WebCam`, `DroidCam Video`, and
  `OBS Virtual Camera`. WSL has USB tools but no `/dev/video0`; `usbipd-win` is
  missing and needs an elevated/admin install.
- Durable machine facts and blockers are recorded in
  `docs/control/win11-dev-host.md`.

## Result

- Final disposition: partial. The host is reachable and has the requested core
  toolchains plus a passing WSL/Linux debug build. Remaining blockers are C:
  free space, Windows symlink/admin privilege for native Windows Flutter builds,
  `usbipd-win` admin install, no attached phones, three failing Flutter tests,
  and no passing Android APK build yet.
