# Evidence Run: Start upload all slave command

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `start-upload-all-slave-command`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Slave WebSocket command starts the manual uploader
- [x] Existing queued media is consumed through the manual upload path
- [x] Screenshot and video proof show the command path

## Device Matrix

- `flutter-test`: macOS Flutter unit-test runner with local WebSocket server and
  the singleton uploader queue.

## Evidence

- RED proof: `flutter test --no-pub test/slave/slave_client_registration_test.dart`
  received `{"command":"startUploadingAll"}` and logged `Unknown JSON command
  type: null`; the queued upload remained pending until the test timed out.
- GREEN proof: the same focused test passes after routing JSON commands with a
  `command` field into `_executeCommand()` and handling `startUploadingAll` via
  `UploaderService().startUploadingManually()`.
- The focused test intentionally leaves `SessionManager.sessionGuid` null, so
  the proof shows command dispatch and queue consumption without making a
  backend upload request.
- Screenshot: `screenshots/start_upload_all_slave_command.png`
- Video: `video/start_upload_all_slave_command_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. Slaves now accept the
  `startUploadingAll` WebSocket command and start the existing manual uploader
  path. Keep item 4 open for in-flight network cancellation and slave upload
  info.
