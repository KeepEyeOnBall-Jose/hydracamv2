# Evidence Run: Win11 Windows/Linux/Android HydraCam camera and master-slave proof

- Source: user-request: native Windows, WSL Linux, Android emulator capture/upload and master/slave combinations
- Slug: `win11-triple-platform-camera-master-slave`
- Verification tier: C (multi-device-emulated-cluster)
- Status: partial pass; Android and full matrix blocked

## Acceptance Checks

- [x] Native Windows HydraCam captures one photo and one short video from webcam or records a real camera-access blocker with fallback media
- [x] WSL Linux HydraCam captures one photo and one short video from webcam or records a real camera-access blocker with fallback media
- [x] Android emulator HydraCam captures one photo and one short video from webcam or records a real camera-access blocker with fallback media
- [x] Windows, Linux, and Android emulator are exercised as master and slave in all ordered combinations, or blockers are documented with a fallback plan

## Device Matrix

- Windows native: Win11 host `jose@100.110.8.112`, `USB2.0 HD UVC WebCam`, automation target `windows-native`.
- Linux native: Ubuntu-22.04 WSL2. Real webcam is blocked because `/dev/video*` is absent and `v4l2-ctl` cannot open `/dev/video0`; WSLg is available. Fallback proof used `HYDRACAM_MOCK_CAMERA=true` plus real predefined media from the Windows webcam run.
- Android emulator: `HydraCam_API33_x86_64`, `emulator-5554` when booted. Host webcam mapping reports `webcam0` as `USB2.0 HD UVC WebCam`, but the AVD exits before the app install/capture probe can run. The same exit occurs with the emulator synthetic camera fallback.

## Evidence

- Windows real-webcam pass:
  - Summary: `remote-windows/windows-real-after-gallery-fix/summary-postprocessed.json`
  - Photo: `remote-windows/windows-real-after-gallery-fix/media/camera_desktop_2_27806114755600.jpg`
  - Video: `remote-windows/windows-real-after-gallery-fix/media/camera_desktop_video_27806454733800.mp4`
  - Backend session GUID: `575c2ab5-fce0-429a-8f93-8ee31c12260a`
  - Upload evidence: `uploadedLineCount=8`, `failedUploadLineCount=0`
- Linux predefined-media fallback pass:
  - Summary: `remote-linux/linux-mock-media-master/summary.json`
  - Photo: `remote-linux/linux-mock-media-master/media/mock_1_2026-06-08T21-59-37-548360.jpg`
  - Video: `remote-linux/linux-mock-media-master/media/mock_2_2026-06-08T21-59-41-921430.mp4`
  - Upload evidence: `uploadedLineCount=8`, `failedUploadLineCount=0`
  - Environment repairs performed: installed a separate Linux Flutter SDK under `/home/jose/flutter-linux`; installed `libsecret-1-dev` through `wsl -u root`; added `HYDRACAM_MOCK_MEDIA_SOURCE_DIR` support in `lib/services/camera_service.dart`.
- Android blocker:
  - Webcam attempt summary: `remote-android/android-emulator-existing-apk/summary.json`
  - Synthetic-camera attempt summary: `remote-android/android-emulator-emulated-camera/summary.json`
  - Emulator boot logs: `remote-android/android-emulator-restart-headless/` and `remote-android/android-emulator-restart-emulated-camera/`
  - Both app probes failed with `adb.exe: device 'emulator-5554' not found` after the AVD had briefly reported boot complete.

## Result

- Final disposition: Windows native real-webcam capture/upload passed. Linux native capture/upload passed only through a predefined real-media fallback because WSL has no camera device. Android emulator capture/upload is blocked by emulator instability before app launch. The requested full Windows/Linux/Android master/slave matrix is blocked until the Android emulator remains alive and Linux gets either USB camera forwarding or the predefined-media fallback is accepted for matrix-only validation.
