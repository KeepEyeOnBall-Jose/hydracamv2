# Evidence Run: 11. Make mobile Auth0 login recoverable and release-safe

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `auth0-refresh-scope`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Auth0 login requests offline_access
- [x] Requested scopes are covered by a focused test
- [x] Screenshot and video proof attached

## Device Matrix

- `flutter-test`: macOS Flutter unit-test runner for the AuthService scope
  contract. The test does not invoke the Auth0 browser/plugin flow.

## Evidence

- RED proof: `flutter test --no-pub test/services/auth0_service_test.dart`
  failed because `AuthService.authorizationScopes` did not exist and the
  request scopes were embedded inline.
- GREEN proof: the focused test passes after `AuthService.authorizationScopes`
  includes `offline_access` and the `AuthorizationTokenRequest` uses that shared
  scope list.
- Screenshot: `screenshots/auth0_refresh_scope.png`
- Video: `video/auth0_refresh_scope_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. The mobile Auth0 request now asks for
  refresh-capable scopes. Credential storage, startup restore, token refresh,
  and real-device login smoke evidence remain separate parts of item 11.
