# Evidence Run: Restore previous-session uploads through storage identifier

- Source: docs/control/backlog-import.md#row-35-old-media-attachment
- Slug: `previous-session-upload-storage-identifier`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Upload-confirm restore uses storageIdentifier when metadata folder differs from backend GUID
- [x] Restored session keeps backend session GUID as active upload identity
- [x] No failed-load snackbar appears for storage-key restore uploads

## Device Matrix

- Not required for tier D integration/unit coverage.

## Evidence

- Red regression: `flutter test --no-pub test/screens/session_details_screen_test.dart --plain-name "upload confirm action restores through storage identifier"` failed before the upload restore path used the storage identifier.
- Green focused coverage: `flutter test --no-pub test/screens/session_details_screen_test.dart test/services/session_manager_test.dart` passed after the fix.
- Analyzer: `flutter analyze --no-pub` passed after removing an unnecessary import.
- Full suite: `flutter test --no-pub` passed.
- Diff hygiene: `git diff --check` passed.

## Result

- Final disposition: passed. Previous-session upload actions now use the storage directory key for metadata lookup while preserving the backend session GUID as the active upload identity.
