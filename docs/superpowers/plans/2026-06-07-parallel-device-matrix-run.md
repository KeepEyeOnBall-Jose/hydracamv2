# Parallel HydraCam Device Matrix Plan

## Summary

Run the camera-setting validation in two layers: first parallelize local checks,
then run one coordinated all-device capture matrix. The current scripts can run
several devices near the same time, but not a true all-at-once matrix yet
because the automation bridge is hard-coded to port `4762` and single-device
scripts start when each device is ready. Implement a small parallel runner first
so every device reaches a ready barrier before capture commands are sent.

## Key Changes

- Add configurable automation bridge port:
  - Change `automationServerPort` to
    `int.fromEnvironment("HYDRACAM_AUTOMATION_PORT", defaultValue: 4762)`.
  - Update `scripts/ios_capture_repro.py` so `--port` is also passed as
    `--dart-define=HYDRACAM_AUTOMATION_PORT=<port>` during `flutter run`.
- Add `scripts/run_parallel_device_matrix.py`:
  - Discover/validate current targets from `flutter devices` and
    `adb devices -l`.
  - Exclude Chrome; include iOS simulator as launch/UI-only because it has no
    camera.
  - Require explicit physical iOS hosts, no `--host auto`.
  - Use unique Android ADB forward ports and unique local macOS/simulator bridge
    ports.
  - Build/install/launch first, wait for every bridge to be healthy, then start
    the capture scenario through a shared barrier.
  - Write per-device artifacts plus `summary.json` and `summary.md` under
    `logs/verification-runs/<timestamp>-parallel-device-matrix/`.

## Matrix To Run

- Android, independent local capture, `autoBack + standard1080p30`:
  - `29d816ac550b7ece` SM-G960F
  - `RF8M21J8XRT` SM-G970F
  - `RF8M90QE7LX` SM-G970F
  - `9885e6503930304946` SM-G935F/S7, expected-current blocker if
    Exynos/Camera2 timeout signature repeats
- iOS/macOS:
  - iPhone 12 Pro `00008101-000A68811E43001E`, host `192.168.178.141`,
    `ultraWide + sport1080p60`
  - iPad 5 `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, host
    `192.168.178.104`, `autoBack + standard1080p30`
  - macOS `macos`, `127.0.0.1:<unique port>`, `autoBack + standard1080p30`
  - iOS simulator `5CF4A12E-A8B5-4285-AE86-407B9067CB5F`,
    `127.0.0.1:<unique port>`, launch/UI-only

## Execution Order

- Run local checks in parallel where safe:
  - `flutter analyze`
  - `flutter test test/services/camera_capture_settings_test.dart test/screens/capture_settings_screen_test.dart`
  - Python compile/unit checks for the new runner.
- Build once for Android with automation enabled.
- Clean test ports and ADB forwards, then launch apps.
- Wait until all device bridges report `/healthz`.
- Apply settings on all targets.
- Concurrently execute: `start_local_session`, `take_photo`,
  `start_recording`, wait 4 seconds, `stop_recording`, `end_session`.
- Accept the run only if each pass-capable target records one photo and one
  video, `/settings.videoCaptureTarget` matches the expected label, physical iOS
  evidence uses the configured bridge host and `/var/mobile/...` trace path, and
  command skew is recorded in the summary.

## Test Plan

- Unit-test runner target classification, port allocation, physical iOS host
  enforcement, simulator launch-only classification, and S7 known-blocker
  classification.
- Dry-run the runner before touching devices.
- Run `flutter analyze`, focused Flutter tests, Python runner tests, and
  `git diff --check`.
- Real-device acceptance is the generated evidence pack; analyzer/unit tests are
  not enough for this matrix.

## Assumptions

- This is an independent local capture matrix on every device, not a
  master-slave broadcast protocol test.
- Chrome is out of scope for camera capture.
- Build/launch may be staged to avoid Flutter/Xcode build races; the actual
  capture scenario is the part that must start from a shared all-device barrier.
