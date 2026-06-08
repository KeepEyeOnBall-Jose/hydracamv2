# Evidence Run: HCMETA-002

- Source: codex
- Slug: `camera-leveling-remaining-device-gaps`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [ ] Retake or strengthen remaining camera setup evidence: physical iPhone availability, S7 edge visible preview if possible, and short recording metadata proof on reachable devices.
  - Partial: S7 was retested from a fresh current-code setup APK and still
    shows a black preview background. Physical iPhone remains unavailable to
    CoreDevice/Flutter. Physical iPad short recording metadata now proves
    `captureContext` persistence with level and perspective fields.

## Device Matrix

- Android SM G935F / Android 8.0.0 API 26 / `9885e6503930304946` /
  setup-preview retake for S7 black preview.
- iPhone 12 Pro / iOS 26.5 / `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A` /
  physical iPhone availability blocker.
- iPad (5) / iOS 17.7.11 / `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` /
  short recording metadata proof.

## Evidence

- `commands.log`: current device discovery, fresh current-code setup APK build,
  S7 install/permission/launch/logcat, physical iPhone lock-state and xctrace
  probes, and iPad app relaunch.
- `screenshots/android-sm-g935f-setup-retake.png`: S7 setup UI retake after a
  fresh APK install and longer warm-up; red tilt overlay is live but preview
  background remains black.
- `device-logs/android-sm-g935f-setup-retake-logs.json`: S7 in-app logs show
  setup role, granted permissions, setup screen navigation, and
  `Camera successfully initialized`.
- `commands.log` also contains S7 CameraX/cameraserver lines with
  `ERROR_MAX_CAMERAS_IN_USE` during the retake window, which is stronger
  evidence than the earlier black screenshot alone.
- `device-logs/ipad-after-metadata-recording-session.json`: iPad session
  snapshot after recording, showing `videoCount=1` and `queueLength=1`.
- `device-logs/ipad-after-metadata-recording-logs.json`: iPad logs with camera
  initialization, recording start, video save path, and metadata save path.
- `device-logs/ipad-metadata-proof-metadata.json`: copied physical iPad
  `metadata.json`; the recorded video contains `captureContext` with
  `cameraPerspectiveId=unknown`, `sensorAvailable=true`, roll `54.729...`,
  pitch `1.556...`, back camera name, sensor orientation `90`,
  `videoCaptureProfile=standard1080p30`, and the iPad device id.
- Physical iPhone probes:
  - `flutter devices` still reports José Ramón's iPhone with the unlock/cable/
    Developer Mode LAN error.
  - `devicectl device info lockState` cannot locate the unavailable CoreDevice
    identifier.
  - `xcrun xctrace list devices` lists José Ramón's iPhone under Devices
    Offline.

## Result

- Final disposition: partial. This iteration improves proof for the reachable
  devices by adding current-code S7 diagnostics and physical iPad recording
  metadata. The full objective remains open because the physical iPhone is not
  reachable and the S7 preview remains black despite successful app-side camera
  initialization.
