# Evidence Run: Improve upload failure, cancel, requeue, and progress UI

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `failed-upload-visible-state`
- Verification tier: B (emulator-simulator-e2e)
- Status: partial

## Acceptance Checks

- [x] Failed uploads show a visible state in media lists
- [x] Pending uploads remain visually distinct from failed uploads
- [x] Focused widget test covers failed upload display
- [x] Screenshot and video proof show the failed state

## Device Matrix

- `flutter-test`: macOS Flutter widget test runner for media-list upload-state
  proof.

## Evidence

- Screenshot: `screenshots/failed_upload_visible_state.png`
- Video: `video/failed_upload_visible_state_proof.mp4`
- Device/test log: `device-logs/flutter-widget-runner.log`
- Commands: `commands.log`
- RED proof: focused media-list widget test failed because failed uploads had
  no visible state.
- GREEN proof: focused media-list widget test passes after adding failed and
  pending labels/icons.
- Analyzer: `flutter analyze --no-pub` passes.

## Result

- Final disposition: partially completed. Failed uploads now render a distinct
  visible state in media lists. Keep the existing board item open for
  cancel/requeue controls, bytes/time estimates, start-upload commands, and
  slave upload info.
