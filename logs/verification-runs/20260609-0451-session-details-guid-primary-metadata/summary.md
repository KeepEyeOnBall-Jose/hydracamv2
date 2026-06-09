# Evidence Run: JAVI IMMEDIATE BACKLOG row 35

- Source: docs/control/backlog-import.md row 35
- Slug: `session-details-guid-primary-metadata`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] SessionDetails metadata uses CaptureSession.preferredIdentifier as the primary session reference and labels legacy sessionId only as legacy when a backend GUID exists

## Device Matrix

- Flutter widget test surface; `test/screens/session_details_screen_test.dart`;
  simulated details UI; macOS Flutter test runtime.

## Evidence

- `flutter test test/screens/session_details_screen_test.dart --plain-name
  "session details metadata uses guid as primary session reference"` passed.
- `flutter test test/screens/session_details_screen_test.dart` passed.

## Result

- Final disposition: passed for local SessionDetails GUID-primary metadata
  display; broader real old-media attachment smoke evidence remains open.
