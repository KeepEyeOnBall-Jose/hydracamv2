# Evidence Run: Camera setup preview and leveling matrix continuation

- Source: docs/control/status-and-roadmap.md#current-mobile-status
- Slug: `camera-leveling-device-continuation`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [x] S7 setup preview either renders live camera video or records a concrete camera/runtime blocker with logs
- [x] Physical iPhone setup proof is retried against current CoreDevice state
- [x] Reachable device screenshots and logs are refreshed for the active camera-leveling objective

## Device Matrix

- Samsung SM-G935F / Android 8.0.0 API 26 / `9885e6503930304946` /
  S7 setup-preview retest.
- Physical iPhone 12 Pro / iOS 26.5 /
  `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A` CoreDevice identifier /
  physical iPhone setup proof retry.
- Physical iPad 5 / iOS 17.7.11 /
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` /
  reachable physical iOS comparison.
- Samsung SM-G960F / Android 10 API 29 / `29d816ac550b7ece` /
  reachable Android comparison.
- Samsung SM-G970F / Android 12 API 31 / `RF8M90QE7LX` /
  reachable Android comparison.
- macOS / macOS 26.4.1 / `macos` /
  reachable desktop setup UI comparison.

## Evidence

- Code change: setup preview now uses `CameraService.prepareCameraPreview()`,
  which initializes the selected preview camera without explicit FPS. Photo and
  video capture still call the normal explicit-FPS readiness path.
- Focused test: `flutter test test/services/camera_service_failure_test.dart`
  passed after adding coverage for preview-default FPS and recording-after-
  preview explicit FPS rebuild.
- First S7 retake after the code change still showed a black preview:
  `screenshots/android-sm-g935f-default-fps-preview.png`. App logs showed
  `Camera preview successfully initialized without explicit fps`, but logcat
  and `dumpsys media.camera` still showed repeated CameraX/cameraserver
  `ERROR_MAX_CAMERAS_IN_USE` / `Too many other clients connecting` rejects.
- Rebooting only the S7 reset the vendor camera service. After relaunching the
  same APK, the S7 rendered the live setup camera preview with red tilt
  guidance: `screenshots/android-sm-g935f-post-reboot-clean-preview.png`.
- S7 post-reboot video evidence:
  `video/android-sm-g935f-post-reboot-preview.mp4`.
- S7 app-side proof:
  `device-logs/android-sm-g935f-post-reboot-health.json` and
  `device-logs/android-sm-g935f-post-reboot-app-logs.json`.
- S7 camera-service proof:
  `device-logs/android-sm-g935f-post-reboot-clean-dumpsys-camera.txt` and
  `device-logs/android-sm-g935f-post-reboot-clean-logcat.txt`.
- Physical iPhone proof was retried with `flutter devices`,
  `xcrun devicectl list devices`, `xcrun xctrace list devices`, and
  `xcrun devicectl device info lockState --device
  AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`. The iPhone remains offline/
  unavailable to CoreDevice, and lock-state lookup failed with CoreDevice error
  1011, so no physical iPhone setup screenshot can be produced from current
  device state.
- Validation passed:
  `flutter analyze`,
  `flutter test test/services/camera_service_failure_test.dart
  test/widgets/camera_setup_preview_screen_test.dart`,
  `flutter test test/services/settings_service_test.dart
  test/services/session_manager_test.dart
  test/platform/multi_device_orchestration_test.dart
  test/screens/master_video_recording_screen_test.dart`, and
  `git diff --check`.

## Result

- Final disposition: partial.
- The continuation made the S7 setup-preview state better and evidenced: live
  local preview now renders after resetting the S7 camera HAL, and the app
  still shows the red warn-only level overlay while the phone is tilted.
- The physical iPhone portion remains externally blocked by device
  availability, not by a current HydraCam app failure.
- S7 capture reliability is still not proven by this pack; this pack covers the
  local placement/setup preview path only.
