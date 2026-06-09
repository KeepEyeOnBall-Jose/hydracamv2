# Evidence Run: Branch compile repair for backend sessions and locale override

- Source: test/services/session_manager_test.dart test/services/app_locale_service_test.dart test/l10n/app_localizations_test.dart
- Slug: `branch-compile-repair-backend-session-locale`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Backend-created session APIs compile and reject local session GUIDs
- [x] Uploader refuses upload work for sessions that are explicitly not backend-created
- [x] Locale override service and seeded localizations satisfy active settings tests
- [x] App shell widgets tolerate legacy test harnesses without localization delegates

## Device Matrix

- MacBook host, macOS 26.4.1 arm64, unit-test runner.

## Evidence

- Red state: analyzer and full-suite runs failed on backend-created session API
  compile gaps, locale service/localization compile gaps, and bare widget
  harnesses crashing in `HydraCamAppBar` after app-shell localization.
- Focused green tests: `flutter test test/services/session_manager_test.dart
  test/services/uploader_service_test.dart test/services/app_locale_service_test.dart
  test/l10n/app_localizations_test.dart test/screens/capture_settings_screen_test.dart`
  passed after the backend-session, upload-guard, locale-service, and seeded
  localization fixes.
- Focused runtime regression tests: `flutter test
  test/widgets/hydra_cam_app_bar_test.dart
  test/camera_singleton_initialization_test.dart
  test/slave/slave_screen_fast_connect_test.dart
  test/automation/automation_standby_screen_test.dart
  test/slave/slave_client_registration_test.dart` passed after app-bar
  localization fallback repair.
- Repo gates: `git diff --check`, `flutter analyze --no-pub`, and full
  `flutter test` passed.

## Result

- Final disposition: backend-created session, upload guard, and locale override
  branch changes compile and pass the full unit/widget suite.
