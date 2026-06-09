# Evidence Run: 11. Make mobile Auth0 login recoverable and release-safe

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `login-desktop-auth0-message`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Login UI shows the explicit mobile-only Auth0 message on unsupported desktop targets
- [x] Generic login failure text is not shown for unsupported desktop Auth0 login
- [x] Focused login-screen widget test passes

## Device Matrix

- Flutter login-screen widget test runner; macOS test host; verification role.

## Evidence

- `dart format lib/screens/login_screen.dart test/screens/login_screen_test.dart`
  passed.
- Source search recorded the `UnsupportedError` UI branch and focused widget
  regression.
- `flutter test --no-pub test/screens/login_screen_test.dart` passed.

## Result

- Final disposition: passed for local unsupported-platform login UI coverage;
  broader Android/iOS mobile smoke evidence remains open.
