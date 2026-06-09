# Evidence Run: Prevent stale uploads from crossing sessions

- Source: docs/control/backlog-import.md#3-prevent-stale-uploads-from-crossing-sessions
- Slug: `uploader-reset-progress-hygiene`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Uploader reset clears queued stale work
- [x] Uploader reset clears current upload state
- [x] Uploader reset clears visible upload progress
- [x] Regression test covers reset behavior

## Device Matrix

- `flutter-test`: macOS Flutter service/widget test runner for uploader reset
  state proof.

## Evidence

- Screenshot: `screenshots/uploader_reset_progress.png`
- Video: `video/uploader_reset_progress_proof.mp4`
- Device/test log: `device-logs/flutter-service-runner.log`
- Commands: `commands.log`
- RED proof: focused uploader test failed because `uploadProgressNotifier`
  stayed at `0.73` after `reset()`.
- GREEN proof: focused uploader test passes after `reset()` clears progress to
  `0.0`.
- Analyzer: `flutter analyze --no-pub` passes.

## Result

- Final disposition: partially completed. Reset hygiene now clears queue,
  current upload state, estimated time, and visible progress. Keep the existing
  board item open for any deeper in-flight upload/session GUID cancellation or
  server-side race proof.
