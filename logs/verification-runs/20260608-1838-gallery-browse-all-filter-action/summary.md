# Evidence Run: Improve old-media/gallery session attachment

- Source: docs/control/backlog-import.md#9-improve-old-media-gallery-session-attachment
- Slug: `gallery-browse-all-filter-action`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Gallery filter dialog offers a no-filter browse action
- [x] Browse All returns filters with no date or duration constraints
- [x] Existing filtered Apply action remains available
- [x] Screenshot and video proof show the no-filter action

## Device Matrix

- `flutter-test`: macOS Flutter widget-test runner for gallery filter dialog.

## Evidence

- RED proof: `flutter test --no-pub test/widgets/media_filter_dialog_test.dart`
  failed because `Browse All` was not present.
- GREEN proof: focused dialog test passes after adding a no-filter action that
  returns `MediaFilters` with no date or duration constraints.
- Existing filtered `Apply` action remains visible.
- Full suite: `flutter test --no-pub` passes.
- Analyzer: `flutter analyze --no-pub` passes.
- Screenshot: `screenshots/gallery_browse_all_filter_action.png`
- Video: `video/gallery_browse_all_filter_action_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. Gallery import can now proceed from
  the filter dialog without requiring specific date/duration constraints. Keep
  item 9 open for candidate-session display and attach-metadata corruption
  proof.
