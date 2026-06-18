# Evidence Run: Uploader cancellation session notification

- Source: docs/control/backlog-import.md#upload-cancellation-and-retry
- Slug: `uploader-cancel-session-notify`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Queued upload cancellation notifies SessionManager listeners after marking media cancelled.
- [x] Active upload cancellation notifies SessionManager listeners after marking media cancelled.

## Device Matrix

- No device matrix for this Tier D service/UI-notification regression. Hardware
  UI smoke was skipped because no mobile devices were currently
  attached/responsive.

## Evidence

- `flutter test test/services/uploader_service_test.dart --name "notifies session listeners"` failed red before the fix.
- The same targeted notification tests passed after the fix.
- `flutter test test/services/uploader_service_test.dart` passed.
- `flutter analyze` passed.
- `flutter test` passed.

## Result

- Final disposition: passed. Queued and active upload cancellation now persist
  the updated media state and notify `SessionManager` listeners so session-backed
  media rows can refresh immediately.
