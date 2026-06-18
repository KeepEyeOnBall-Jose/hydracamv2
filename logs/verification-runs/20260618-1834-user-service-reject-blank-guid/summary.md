# Evidence Run: Reject blank backend user GUIDs

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `user-service-reject-blank-guid`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] UserService.login rejects blank backend GUID lookups
- [x] UserService.restoreStoredSession rejects blank backend GUID lookups
- [x] Rejected blank GUIDs leave no logged-in in-memory user

## Device Matrix

- Not applicable. Tier D service coverage for Auth0/backend identity mapping.

## Evidence

- Red/green regression test:
  `flutter test --no-pub test/services/user_service_test.dart` first failed
  because whitespace-only backend GUID lookups marked login/restore as logged
  in, then passed after backend GUID lookup results were normalized before
  accepting them.
- Broader checks passed:
  `flutter test --no-pub test/services/user_service_test.dart test/services/auth0_service_test.dart test/screens/login_screen_test.dart`,
  `flutter analyze --no-pub`,
  `git diff --check`, and `flutter test --no-pub`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. Blank backend GUID lookup results now clear
  in-memory user state instead of creating a false logged-in user.
