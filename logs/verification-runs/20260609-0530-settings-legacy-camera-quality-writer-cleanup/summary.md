# Evidence Run: settings legacy camera quality writer cleanup

- Source: lib/services/settings_service.dart legacy getCameraQuality/setCameraQuality API
- Slug: `settings-legacy-camera-quality-writer-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Legacy SettingsService camera-quality callers read/write through canonical videoCaptureProfile storage, and setting a canonical profile clears stale cameraQuality values.

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
