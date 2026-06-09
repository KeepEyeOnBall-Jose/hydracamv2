# Evidence Run: Master video stop handler async cleanup

- Source: cleanup scan: async void recording screen handler
- Slug: `master-video-stop-handler-async-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] MasterVideoRecordingScreen stop button awaits onStopRecording and returns captured video
- [ ] Stop handler returns Future<void> and UI callbacks dispatch it explicitly
- [ ] Focused recording screen test, analyzer, diff check, and full Flutter tests pass

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
