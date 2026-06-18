# Evidence Run: Master recording interruption listener cleanup

- Source: docs/control/backlog-import.md#recording-and-session-cleanup
- Slug: `master-recording-listener-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Master recording preview removes its recording interruption listener when disposed.

## Device Matrix

- No device matrix for this Tier D widget/lifecycle regression. Hardware UI
  smoke was skipped because no mobile devices were currently
  attached/responsive.

## Evidence

- `flutter test test/screens/master_video_recording_screen_test.dart --name "recording interruption listener is removed on dispose"` failed red before the fix.
- The same targeted regression passed after the fix.
- `flutter test test/screens/master_video_recording_screen_test.dart` passed.
- `flutter analyze` passed.
- `flutter test` passed.

## Result

- Final disposition: passed. The master recording preview now removes the exact
  `recordingInterrupted` listener it added, handles camera service swaps, and
  ignores interruption callbacks after disposal.
