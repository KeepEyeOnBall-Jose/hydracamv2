# Camera Lens and Video Profile Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each HydraCam phone choose a local camera lens and target video profile before recording, with iPhone 12 Pro+ and Samsung S7+ behavior handled through capability-based fallbacks.

**Architecture:** Store lens and video profile preferences in `SettingsService`, resolve them inside `CameraService` whenever a controller is created, and keep master/slave WebSocket commands unchanged. iOS uses `CameraDescription.lensType` for ultra-wide/wide/telephoto labels; Android enriches opaque camera IDs with Camera2 metadata when available and otherwise falls back to preview-based manual selection.

**Tech Stack:** Flutter, Dart, `camera` 0.11.4, `camera_avfoundation` 0.9.23+2, `camera_android_camerax` 0.6.30, Android Camera2 metadata, iOS AVFoundation metadata.

---

## Tasks

### Task 1: Settings Model and Persistence

**Files:**
- Create: `lib/models/camera_capture_settings.dart`
- Modify: `lib/services/settings_service.dart`
- Test: `test/services/camera_capture_settings_test.dart`, `test/services/settings_service_test.dart`

- [x] Add `LensPreference` values: `autoBack`, `ultraWide`, `wide`, `telephoto`, `front`.
- [x] Add `VideoCaptureProfile` values: `dataSaver480p30`, `compat720p30`, `standard1080p30`, `sport1080p60`, `detail4k30`, `pro4k60`.
- [x] Persist `cameraLensPreference`, `selectedCameraName`, and `videoCaptureProfile`.
- [x] Migrate legacy `cameraQuality`: `low -> dataSaver480p30`, `medium -> compat720p30`, `high/default -> standard1080p30`.

### Task 2: Camera Service Wiring

**Files:**
- Modify: `lib/services/camera_service.dart`
- Test: `test/services/camera_service_failure_test.dart`

- [x] Resolve selected camera by stored camera name first, then lens preference, then first back camera, then first available camera.
- [x] Create `CameraController` with selected profile resolution and `fps`.
- [x] Preserve selected camera/lens when changing profile.
- [x] Add `setLensPreference()` and `setVideoCaptureProfile()` service methods.

### Task 3: Settings and Camera Selection UI

**Files:**
- Modify: `lib/screens/settings_screen.dart`, `lib/screens/camera_selection_screen.dart`
- Test: `test/screens/capture_settings_screen_test.dart`

- [x] Replace "Camera Quality" with "Capture Settings".
- [x] Add dropdowns for camera lens and video profile.
- [x] Show target summary such as `Target: 1080p at 30 fps`.
- [x] Label iOS lenses as `Ultra Wide (0.5x)`, `Wide (1x)`, and `Telephoto`.
- [x] Show Android Camera2 focal-length/zoom metadata when available.

### Task 4: Native Metadata Hooks

**Files:**
- Create: `lib/services/camera_hardware_metadata_service.dart`, `lib/services/video_metadata_service.dart`
- Modify: `android/app/src/main/kotlin/com/amaia23/hydracam/MainActivity.kt`, `ios/Runner/AppDelegate.swift`
- Test: `test/services/camera_hardware_metadata_service_test.dart`

- [x] Add Android `hydracamv2/camera_metadata` channel for focal lengths and max digital zoom.
- [x] Add Android/iOS `hydracamv2/video_metadata` channel for saved-video width, height, duration, and fps where available.
- [x] Log actual recorded metadata after video save without failing the recording flow if metadata is unavailable.

### Task 5: Verification

**Files:**
- Modify: `docs/control/backlog-import.md`, `docs/control/status-and-roadmap.md`

- [x] Add ASAP control-plane item for real-device iPhone 12 Pro and Samsung S7/S10e proof.
- [x] Run targeted unit/widget tests.
- [x] Run `flutter analyze`.
- [x] Run local compile checks: `flutter test`, `flutter build apk --debug`, and `flutter build ios --debug --no-codesign`.
- [ ] Run real-device evidence pack: iPhone 12 Pro ultra-wide 1080p60 + 4K30, Samsung S7 rear wide 1080p60 + 4K30, metadata logs captured.

## Local Verification

2026-06-07:
- `flutter analyze` passed with no issues.
- `flutter test` passed.
- `flutter build apk --debug` built `build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter build ios --debug --no-codesign` built `build/ios/iphoneos/Runner.app`.

Known remaining gap: device evidence still needs to prove the actual lenses,
resolution, and fps on iPhone 12 Pro and Samsung S7/S10e hardware.

2026-06-07 device-matrix re-verification:
- Evidence root:
  `logs/verification-runs/20260607-camera-settings-device-matrix/`.
- Passed: macOS controller/mock-camera path with `standard1080p30`; physical
  iPad with `autoBack` + `standard1080p30`, one photo and one video captured.
- Partial pass: Samsung S10e with `autoBack` + `standard1080p30` captured one
  photo and one video and logged `1920x1080, unknown fps`, but automation
  session end left the session active.
- Blocked/failed: iPhone 12 Pro launch is blocked until the device is unlocked;
  Xiaomi 2201116PG install is blocked by `INSTALL_FAILED_USER_RESTRICTED`;
  Samsung S7 baseline and 1080p60 capture hit native Camera3/Exynos buffer
  timeouts; S10e 1080p60 also hit native Samsung/Exynos camera errors.
- The original real-device acceptance target remains open until iPhone 12 Pro
  ultra-wide 1080p60/4K30 and Samsung S7 rear-wide 1080p60/4K30 pass with
  actual metadata logs.

2026-06-07 rerun after automation/camera-timeout fixes:
- Evidence root:
  `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/`.
- Passed: Samsung S10e `autoBack` + `standard1080p30` now captures one photo,
  one video, logs `1920x1080, unknown fps, 4014 ms`, and ends the local
  automation session cleanly; physical iPad again captures one photo and one
  video at `autoBack` + `standard1080p30`; macOS mock/controller path passes.
- A final current-build S10e `autoBack` + `standard1080p30` smoke after the
  automation field-order patch also passed after reinstalling the debug APK,
  logging `1920x1080, unknown fps, 3866 ms` and ending inactive.
- Failed with bounded timeout: S10e `sport1080p60`, S7 `standard1080p30`, and
  S7 `compat720p30`. The previous disposed-controller crash did not recur; the
  S7 failure at 720p30 shows a baseline CameraX/device path issue, not only a
  high-FPS issue.
- Blocked: iPhone 12 Pro `ultraWide` + `sport1080p60` still lacks capture
  evidence because Flutter/Xcode timed out starting the debug session and
  direct `devicectl` launch was denied while the phone was locked. Xiaomi
  2201116PG still blocks APK install with `INSTALL_FAILED_USER_RESTRICTED`.
- iOS saved-video metadata remains unavailable in the physical iPad run.
