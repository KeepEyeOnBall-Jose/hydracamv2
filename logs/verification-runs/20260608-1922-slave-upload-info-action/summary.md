# Evidence Run: 4. Improve upload failure, cancel, requeue, and progress UI

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `slave-upload-info-action`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Slave app bar exposes uploader info directly
- [x] Direct uploader action opens UploaderInfoScreen
- [x] Focused widget test, screenshot, and video proof attached

## Device Matrix

- `flutter-test`: macOS Flutter widget-test runner with a fake slave client and
  mock camera service.

## Evidence

- RED proof: `flutter test --no-pub
  test/slave/slave_screen_fast_connect_test.dart` failed because
  `find.byTooltip("Uploader Info")` found zero widgets on `SlaveScreen`.
- GREEN proof: the same focused test passes after `SlaveScreen` adds a direct
  `Uploader Info` app-bar action and routes it to `UploaderInfoScreen`.
- Screenshot: `screenshots/slave_upload_info_action.png`
- Video: `video/slave_upload_info_action_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. Slave mode now exposes upload status
  directly from the app bar and the direct action opens the existing uploader
  info screen. Keep item 4 open only for in-flight network cancellation.
