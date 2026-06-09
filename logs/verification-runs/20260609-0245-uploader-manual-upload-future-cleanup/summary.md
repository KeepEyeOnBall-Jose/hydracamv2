# Evidence Run: T-018

- Source: lib/services/uploader_service.dart#startUploadingManually
- Slug: `uploader-manual-upload-future-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Manual upload exposes an awaitable Future that completes after queued uploads drain
- [x] Existing auto/manual upload behavior and cancellation guards remain covered

## Device Matrix

- MacBook host, macOS 26.4.1 arm64, unit-test runner.

## Evidence

- Red test: `flutter test test/services/uploader_service_test.dart` failed to
  compile when the new test awaited `UploaderService.startUploadingManually()`,
  because the method still returned `void`.
- Green focused tests: `flutter test test/services/uploader_service_test.dart
  test/slave/slave_client_registration_test.dart
  test/screens/uploader_info_screen_test.dart
  test/screens/session_details_screen_test.dart` passed after
  `startUploadingManually()`, `_startUploading()`, and `_processNextItem()`
  returned `Future<void>`, and UI/command call sites awaited the manual path.
- Supporting l10n repair: `flutter gen-l10n` refreshed generated localization
  files from existing ARB data after full-suite l10n coverage found stale
  generated Spanish/Polish strings. `flutter test
  test/l10n/app_localizations_test.dart` passed afterward.
- Repo gates: `git diff --check`, `flutter analyze --no-pub`, and full
  `flutter test` passed. One intermediate full-suite attempt crashed in Flutter
  tooling while deleting `ios/Flutter/ephemeral/Packages/.packages`; the next
  full-suite run reached tests and was repaired, and the final full-suite run
  passed.

## Result

- Final disposition: manual upload completion is now awaitable through queue
  drain, while auto-upload remains fire-and-forget and existing cancellation
  guards remain covered.
