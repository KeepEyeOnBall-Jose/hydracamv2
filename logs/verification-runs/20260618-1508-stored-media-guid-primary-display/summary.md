# Stored Media GUID-Primary Display

- Status: `passed`
- Date: `2026-06-18`
- Control-plane item: `docs/control/backlog-import.md` row 35, `Use GUIDs everywhere across controllers/views`
- Scope: stored-media list display and historical-session restore key handling.

## What Changed

- Updated `PreviousSessionsScreen` to load metadata snapshots for stored media
  rows and display `CaptureSession.preferredIdentifier` as the primary
  `Session: ...` label.
- Added a secondary `Legacy Session ID` label when the metadata session ID is
  distinct from the backend GUID.
- Passed the original storage directory identifier into `SessionDetailsScreen`
  so restore uses the folder key when it differs from the metadata GUID.

## Validation

```bash
flutter test --no-pub test/screens/previous_sessions_screen_test.dart --plain-name 'stored media list prefers metadata GUID over storage key'
flutter test --no-pub test/screens/session_details_screen_test.dart --plain-name 'load session action can restore through storage identifier'
flutter test --no-pub test/screens/previous_sessions_screen_test.dart
flutter test --no-pub test/screens/session_details_screen_test.dart
flutter test --no-pub test/services/session_manager_test.dart test/screens/session_details_screen_test.dart test/screens/sessions_screen_test.dart test/services/gallery_session_candidate_source_test.dart test/models/capture_session_test.dart
flutter analyze --no-pub
flutter test --no-pub
```

All commands passed.

## Device Availability

```bash
adb devices -l
flutter devices
```

`adb` reported no attached Android devices. Flutter reported only macOS and
Chrome as connected, with iPad/iPhone wireless discovery unavailable.
