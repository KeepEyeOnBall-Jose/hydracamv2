# Evidence Run: Improve upload failure, cancel, requeue, and progress UI

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `upload-byte-progress-visible`
- Verification tier: B (emulator-simulator-e2e)
- Status: partial

## Acceptance Checks

- [x] Current upload progress shows percentage
- [x] Current upload progress shows uploaded bytes and total bytes when file size is available
- [x] Focused widget test covers byte-level progress
- [x] Screenshot and video proof show byte-level progress

## Device Matrix

- `flutter-test`: macOS Flutter widget test runner for media-list upload
  progress proof.

## Evidence

- Screenshot: `screenshots/upload_byte_progress_visible.png`
- Video: `video/upload_byte_progress_visible_proof.mp4`
- Device/test log: `device-logs/flutter-widget-runner.log`
- Commands: `commands.log`
- RED proof: focused media-list widget test failed because the uploading item
  showed `50%` but not `2 B / 4 B`.
- GREEN proof: focused media-list widget test passes after adding byte-level
  progress text.
- Analyzer: `flutter analyze --no-pub` passes.

## Result

- Final disposition: partially completed. Upload progress now shows byte-level
  progress when file size is available. Keep the existing board item open for
  time estimates, cancel/requeue controls, start-upload commands, and slave
  upload info.
