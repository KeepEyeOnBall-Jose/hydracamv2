# Evidence Run: Harden Auth0 restore/login cleanup and startup backend warm-up

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `auth0-runtime-recoverability`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Auth0 login rejects missing or malformed identity without retaining stale credentials
- [x] User restore/login rejects blank email before GUID lookup
- [x] Startup backend warm-up is non-blocking and covered by tests

## Device Matrix

- macOS host, macOS 26.4.1, `macos`, local test host.
- iPad (5) wireless, iOS 17.7.11,
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, visible but not launched in this
  Tier D auth rerun.
- Jose Ramon iPhone wireless, iOS 26.5,
  `00008101-000A68811E43001E`, visible but not launched in this Tier D auth
  rerun.

## Evidence

- `commands.log` records:
  - `flutter test --no-pub test/services/auth0_service_test.dart test/services/user_service_test.dart test/widget_test.dart test/screens/login_screen_test.dart`
  - `flutter analyze --no-pub`
  - `flutter devices --device-timeout 10`

## Result

- Final disposition: passed for local/static/Tier D validation. No interactive
  mobile Auth0 browser smoke was attempted in this run, so Android/iOS
  process-death, logout, and account-switch proof remain open.
