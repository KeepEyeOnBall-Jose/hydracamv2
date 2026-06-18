# Evidence Run: Reject malformed backend session GUIDs

- Source: docs/control/backlog-import.md#t-016-photo-video-upload-api-test-with-invalid-files
- Slug: `reject-malformed-backend-session-guids`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] createSession rejects non-string backend GUID values
- [x] createSession rejects sentinel backend GUID strings
- [x] SessionManager rejects sentinel service session GUIDs before capture/upload state

## Device Matrix

- Not applicable. Tier D API/session contract coverage.

## Evidence

- Red/green regression test:
  `flutter test --no-pub test/services/hydracam_api_service_test.dart
  test/services/session_manager_test.dart` first failed because non-string
  backend GUID values, sentinel backend GUID strings, and sentinel join-session
  GUIDs were accepted as uploadable sessions. The same focused command passed
  after backend session GUID parsing and `SessionManager.isServiceSessionGuid()`
  were tightened.
- Broader checks passed: `flutter analyze --no-pub`, `flutter test --no-pub`,
  and `git diff --check`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. Malformed backend/session GUIDs now fail before
  creating capture/upload session state.
