# Evidence Run: Ignore stale in-flight upload completion after reset

- Source: docs/control/backlog-import.md#3-prevent-stale-uploads-from-crossing-sessions
- Slug: `stale-inflight-upload-reset-guard`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Reset during an in-flight upload prevents stale completion from marking media uploaded
- [x] Reset during an in-flight upload preserves the new session metadata
- [x] Screenshot and video proof show the stale completion guard

## Device Matrix

- `flutter-test`: macOS Flutter unit-test runner with mocked HTTP upload,
  mocked app metadata, and deterministic path-provider storage.

## Evidence

- RED proof: `flutter test --no-pub test/services/uploader_service_test.dart`
  held the upload HTTP request open, reset the uploader, started a new session,
  then released a successful HTTP response. The old media was incorrectly
  marked uploaded.
- GREEN proof: the same focused test passes after `UploaderService.reset()`
  increments an upload generation and `_processNextItem()` ignores completions
  captured before the reset.
- The test asserts `SessionManager.instance.sessionGuid == "new-session-guid"`,
  the new session has no old photos attached, the old photo remains
  `isUploaded == false`, and uploader current state is clear.
- Screenshot: `screenshots/stale_inflight_upload_reset_guard.png`
- Video: `video/stale_inflight_upload_reset_guard_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. Local in-flight upload completions are
  now ignored after a reset, preventing stale previous-session media state from
  crossing into a new session. Keep item 3 open for server-side race proof.
