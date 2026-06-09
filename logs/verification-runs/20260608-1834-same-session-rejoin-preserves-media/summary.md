# Evidence Run: Preserve session state across master reconnect

- Source: docs/control/backlog-import.md#2-preserve-session-state-across-master-reconnect
- Slug: `same-session-rejoin-preserves-media`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Rejoining the same active session does not clear captured media
- [x] Rejoining the same active session does not reset the uploader queue
- [x] Different session GUIDs still start fresh sessions
- [x] Screenshot and video proof show preserved media

## Device Matrix

- `flutter-test`: macOS Flutter unit-test runner for session manager behavior.

## Evidence

- RED proof: `flutter test --no-pub test/services/session_manager_test.dart`
  failed because rejoining the same session GUID cleared captured photos.
- GREEN proof: focused session-manager tests pass after preserving existing
  media and uploader queue on same-GUID rejoin.
- Regression guard: a different session GUID still starts with clean media and
  an empty queue.
- Full suite: `flutter test --no-pub` passes.
- Analyzer: `flutter analyze --no-pub` passes.
- Screenshot: `screenshots/same_session_rejoin_preserves_media.png`
- Video: `video/same_session_rejoin_preserves_media_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. `SessionManager.startSession()`
  preserves local media and queued uploads when the same active session GUID is
  announced again. Keep item 2 open for a real master/slave reconnect evidence
  pack and cross-device metadata comparison.
