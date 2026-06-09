# Evidence Run: Improve upload failure, cancel, requeue, and progress UI

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `upload-time-estimate-visible`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Current upload progress shows an estimated time remaining when upload timing is known
- [x] Estimate is deterministic in widget tests
- [x] Existing byte progress and upload states remain compatible
- [x] Screenshot and video proof show the time estimate

## Device Matrix

- `flutter-test`: macOS Flutter widget-test runner for media-list upload UI.

## Evidence

- RED proof: `flutter test --no-pub test/widgets/media_list_widget_test.dart`
  failed because `MediaListWidget` had no deterministic `now` hook or time
  estimate label.
- GREEN proof: media-list widget tests pass after adding the deterministic
  time estimate label.
- The first implementation attempt exposed a `ListTile` trailing overflow; the
  estimate now renders in the subtitle while the trailing progress area keeps
  percent and byte progress.
- Full suite: `flutter test --no-pub` passes.
- Analyzer: `flutter analyze --no-pub` passes.
- Screenshot: `screenshots/upload_time_estimate_visible.png`
- Video: `video/upload_time_estimate_visible_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. Current upload rows now show an
  estimated remaining time when progress and upload start time are known. Keep
  item 4 open for true cancel controls, start-upload commands, and slave upload
  info.
