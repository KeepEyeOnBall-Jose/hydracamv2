# Evidence Run: Evidence-first advancement loop tooling

- Source: docs/control/evidence-first-loop.md
- Slug: `evidence-first-loop-tooling`
- Verification tier: B (emulator-simulator-e2e)
- Status: partial

## Acceptance Checks

- [x] Control-plane docs require hardware or emulator evidence for device-facing work
- [x] Evidence helper creates, records, finalizes, and validates run packs
- [x] An iOS simulator run produces screenshot, video, and device-log artifacts

## Device Matrix

- iPhone 16 Plus simulator, iOS 18.4 runtime,
  `5CF4A12E-A8B5-4285-AE86-407B9067CB5F`, single app instance.

## Evidence

- `commands.log`: helper tests, analyzer, iOS simulator integration attempt,
  screenshot capture, simulator log capture, and video capture.
- `screenshots/ios-simulator-after-platform-test.png`: simulator screenshot
  after the attempted integration run.
- `video/ios-simulator-after-platform-test.mp4`: bounded simulator screen
  recording after the attempted integration run.
- `device-logs/ios-simulator-last-10m.log`: simulator logs from the run window.

## Result

- Final disposition: partial. The evidence-first loop tooling and control-plane
  wiring are implemented, and the pack contains simulator screenshot/video/log
  artifacts. The iOS simulator integration run failed in
  `integration_test/platform_test.dart` before app launch assertions passed,
  surfacing an existing app/test blocker that this process should track in a
  future iteration rather than masking with analyzer-only verification.
