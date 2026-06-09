# Evidence Run: settings legacy camera quality migration cleanup

- Source: test/services/settings_service_test.dart and lib/services/settings_service.dart legacy cameraQuality fallback
- Slug: `settings-legacy-camera-quality-migration-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Legacy cameraQuality reads return the mapped VideoCaptureProfile and persist the canonical videoCaptureProfile key, while existing canonical profile values remain authoritative.

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
