# Evidence Run: Win11 Windows/Linux/Android Emulator Webcam Upload and Role Matrix

- Source: user-request: native Windows, WSL Linux, Android emulator webcam/upload and master-slave combinations
- Slug: `win11-triple-platform-webcam-upload-matrix`
- Verification tier: C (multi-device-emulated-cluster)
- Status: partial-pass, role-matrix-blocked

## Acceptance Checks

- [x] Native Windows HydraCam captures and uploads one photo and one short video from the real webcam.
- [x] WSL Linux HydraCam captures and uploads one photo and one short video using documented mock-media fallback. WSL had no `/dev/video*` device.
- [x] Android emulator HydraCam captures and uploads one photo and one short video using documented private mock-media fallback.
- [ ] Windows, Linux, and Android emulator master/slave combinations are fully exercised. Blocked because the Linux standby bridge did not compile/start in the current dirty checkout.

## Device Matrix

- Windows native: `DESKTOP-02NDERS`, Flutter Windows, target `windows-native`, real camera `USB2.0 HD UVC WebCam`, backend session `c0702171-4766-406c-9080-b7059d6bd7b3`.
- Linux: Ubuntu-22.04 WSL2, target `linux-native`, no `/dev/video*`; mock media source used.
- Android: emulator `HydraCam_API33_x86_64` / `emulator-5554`, target `android-emulator`, `webcam0` mapped to `USB2.0 HD UVC WebCam`; real-camera output was zero bytes, private mock media source used for accepted proof.

## Evidence

- Windows real webcam proof:
  - Summary: `remote/windows-real-after-pub-get/summary-postprocessed.json`
  - Photo: `remote/windows-real-after-pub-get/media/camera_desktop_2_49014290942000.jpg` (48,535 bytes)
  - Video: `remote/windows-real-after-pub-get/media/camera_desktop_video_49014529472100.mp4` (1,026,647 bytes)
  - Upload log count: 2 successful media-upload lines, 0 failed-upload lines.
- Linux WSL fallback proof:
  - Summary: `remote/linux-mock-media-master/summary.json`
  - Photo: `remote/linux-mock-media-master/media/mock_1_2026-06-09T02-58-06-284175.jpg` (48,535 bytes)
  - Video: `remote/linux-mock-media-master/media/mock_2_2026-06-09T02-58-10-693602.mp4` (1,026,647 bytes)
  - Upload log count: 8 successful upload-related lines, 0 failed-upload lines.
- Android emulator real webcam blocker:
  - Summary: `remote/android-emulator-existing-apk-webcam0/summary.json`
  - Root-pull summary: `remote/android-emulator-existing-apk-webcam0/media-root-pull-summary.json`
  - Result: app reported capture/upload success, but root-pulled app-private JPEG and MP4 were both 0 bytes.
- Android emulator private fallback proof:
  - Summary: `remote/android-emulator-private-mock-media-fallback/summary.json`
  - Root-pull summary: `remote/android-emulator-private-mock-media-fallback/media-root-pull-summary.json`
  - Photo: `remote/android-emulator-private-mock-media-fallback/media-root-pull/android_private_fallback_photo.jpg` (48,535 bytes)
  - Video: `remote/android-emulator-private-mock-media-fallback/media-root-pull/android_private_fallback_video.mp4` (1,026,647 bytes)
  - Upload log count: 8 successful upload-related lines, 0 failed-upload lines.
- Role matrix attempt:
  - Directory: `remote/role-matrix/`
  - Windows standby bridge reached `status=ok`, target `windows-native`, command `set_role`.
  - Android standby bridge reached `status=ok` during the run, target `android-emulator`, command `set_role`.
  - Linux standby failed to become role-switch ready. `remote/role-matrix/linux-standby/flutter-run.stderr.txt` shows Flutter Linux compile errors in `lib/screens/sessions_screen.dart` and `lib/services/device_level_service.dart`; `remote/role-matrix/health-linux-native.json` records the bridge timeout.

## Result

- Final disposition: capture/upload proof is passed for Windows real webcam and for Linux/Android documented fallback media. The Android emulator real-webcam path is not accepted because it produced zero-byte media. The requested all-combinations master/slave matrix is blocked until the Linux desktop build compiles and exposes its automation bridge.
