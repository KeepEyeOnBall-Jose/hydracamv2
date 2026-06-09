# Evidence Run: Improve upload failure, cancel, requeue, and progress UI

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `pending-upload-cancel-control`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Pending queued uploads can be cancelled from UploaderService
- [x] Media list exposes an explicit cancel action for pending queued media
- [x] Uploader info screen wires cancel actions to the upload queue
- [x] Screenshot and video proof show the cancel control

## Device Matrix

- `flutter-test`: macOS Flutter unit/widget-test runner for upload queue UI.

## Evidence

- RED proof: `flutter test --no-pub test/services/uploader_service_test.dart
  test/widgets/media_list_widget_test.dart` failed because
  `cancelQueuedMedia` and `onCancelVideoUpload` did not exist.
- GREEN proof: focused uploader/media-list tests pass after adding queue
  cancellation plus pending-row cancel controls.
- Integration surface: `UploaderInfoScreen` now wires photo/video cancel
  callbacks to `UploaderService.cancelQueuedMedia()`.
- Full suite: `flutter test --no-pub` passes.
- Analyzer: `flutter analyze --no-pub` passes.
- Screenshot: `screenshots/pending_upload_cancel_control.png`
- Video: `video/pending_upload_cancel_control_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. Pending queued uploads can now be
  cancelled explicitly from media rows. Keep item 4 open for in-flight network
  cancellation, start-upload commands, and slave upload info.
