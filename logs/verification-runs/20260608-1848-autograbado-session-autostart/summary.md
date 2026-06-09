# Evidence Run: Implement autograbado mode

- Source: docs/control/backlog-import.md#8-implement-autograbado-mode
- Slug: `autograbado-session-autostart`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Autograbado starts slave recording when a sessionStarted message arrives
- [x] Autograbado starts only when the persisted setting is enabled
- [x] Existing session registration still happens
- [x] Screenshot and video proof show the autostart behavior

## Device Matrix

- `flutter-test`: macOS Flutter unit-test runner using the mock camera singleton
  and local WebSocket server.

## Evidence

- RED proof: `flutter test --no-pub test/slave/slave_client_registration_test.dart`
  timed out because `sessionStarted` only registered the session and did not
  start recording.
- GREEN proof: focused slave-client tests pass after routing
  `sessionStarted` / `sessionStatus` through setting-gated autograbado start.
- Existing session registration remains covered by asserting
  `SessionManager.instance.sessionGuid == "autograbado-session"`.
- Full suite: `flutter test --no-pub` passes.
- Analyzer: `flutter analyze --no-pub` passes.
- Screenshot: `screenshots/autograbado_session_autostart.png`
- Video: `video/autograbado_session_autostart_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. A slave with persisted autograbado
  enabled now starts recording after joining an active master session. Keep item
  8 open for real-device unattended recording proof and safe stop controls.
