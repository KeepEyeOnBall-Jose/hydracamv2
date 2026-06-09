# Evidence Run: JAVI IMMEDIATE BACKLOG row 35

- Source: docs/control/backlog-import.md row 35
- Slug: `sessions-list-guid-primary-display`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] SessionsScreen uses the backend GUID as the primary session reference in the sessions list and load feedback while labeling a distinct legacy sessionId only as legacy context

## Device Matrix

- Flutter widget test surface on macOS host runtime.
- Mock HydraCam sessions API response with distinct `guid` and legacy
  `sessionId`.
- No physical device required for this Tier D list-display cleanup.

## Evidence

- `commands/flutter-test-test-screens-sessions-screen-test-dart/command.txt`
  captures `flutter test test/screens/sessions_screen_test.dart`.
- `commands/flutter-test-test-screens-sessions-screen-test-dart/stdout.txt`
  records `+2: All tests passed!`.
- Test assertions prove `Session: backend-session-guid` is visible,
  `Legacy Session ID: legacy-session-id` is secondary context, the raw legacy
  ID is not used as the title, and selecting the load action joins
  `backend-session-guid`.

## Result

- Final disposition: local widget proof passed for SessionsScreen GUID-primary
  display/load feedback. Row 35 remains open for real old-media attachment smoke
  evidence and any remaining controller/view GUID audit outside this screen.
