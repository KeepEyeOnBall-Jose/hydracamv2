# Evidence Run: Improve upload failure, cancel, requeue, and progress UI

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `explicit-upload-requeue-actions`
- Verification tier: B (emulator-simulator-e2e)
- Status: partial

## Acceptance Checks

- [x] Failed media has an explicit retry upload action
- [x] Pending media has an explicit queue upload action
- [x] Upload action callbacks still invoke the existing requeue path
- [x] Screenshot and video proof show the explicit actions

## Device Matrix

- `flutter-test`: macOS Flutter widget test runner for media-list upload
  action proof.

## Evidence

- Screenshot: `screenshots/explicit_upload_actions.png`
- Video: `video/explicit_upload_actions_proof.mp4`
- Device/test log: `device-logs/flutter-widget-runner.log`
- Commands: `commands.log`
- RED proof: focused media-list widget test failed because upload action
  tooltips were missing.
- GREEN proof: focused media-list widget test passes after adding retry/queue
  labels while preserving callbacks.
- Analyzer: `flutter analyze --no-pub` passes.

## Result

- Final disposition: partially completed. Failed and pending media now expose
  explicit requeue actions. Keep the existing board item open for true cancel
  controls, time estimates, start-upload commands, and slave upload info.
