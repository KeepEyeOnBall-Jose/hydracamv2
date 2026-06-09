# Evidence Run: 4. Improve upload failure, cancel, requeue, and progress UI

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `inflight-upload-cancel-control`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Active upload can be cancelled from uploader UI
- [x] Cancelling the active upload clears progress/current state
- [x] Late HTTP completion after cancellation cannot mark media uploaded
- [x] Cancelling active upload closes the HTTP client
- [x] Screenshot and video proof attached

## Device Matrix

- `flutter-test`: macOS Flutter widget/service test runner with mocked HTTP,
  path provider, package metadata, and shared preferences.

## Evidence

- RED proof: `flutter test --no-pub test/widgets/media_list_widget_test.dart`
  failed because the active upload row did not expose the `Cancel upload`
  tooltip.
- RED proof: `flutter test --no-pub test/screens/uploader_info_screen_test.dart`
  failed because the real uploader screen had no current-row cancel action.
- RED proof: `flutter test --no-pub test/services/uploader_service_test.dart`
  failed because cancelling the active upload left the configured HTTP client
  open.
- GREEN proof: the focused service, media-list, and uploader-info screen tests
  pass after adding active-row cancel UI, `UploaderService.cancelMediaUpload()`,
  `UploaderService.cancelCurrentUpload()`, and
  `HydraCamApiService.cancelInFlightRequests()`.
- Screenshot: `screenshots/inflight_upload_cancel_control.png`
- Video: `video/inflight_upload_cancel_control_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. Active uploads can now be cancelled
  from the uploader UI; cancellation clears current/progress state, closes and
  replaces the active HTTP client, and ignores any late completion through the
  upload-generation guard.
