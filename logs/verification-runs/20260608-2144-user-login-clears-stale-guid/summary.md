# Evidence Run: T-001: Account switch clears stale GUID

- Source: docs/control/backlog-import.md
- Slug: `user-login-clears-stale-guid`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] UserService.login clears prior logged-in state when a new Auth0 email cannot be mapped to a HydraCam backend GUID, preventing stale account reuse after account switching.

## Device Matrix

- UserService unit test runner, macOS host / Flutter test, role
  `auth-account-switch`, identifier `UserService stale GUID account switch`.

## Evidence

- `commands.log`: captured RED failure where `isLoggedIn` stayed true after an
  unmapped account switch, then GREEN focused UserService test run.
- `device-logs/user-login-stale-guid-test-commands.log`: copy of the test
  command log for the evidence pack device-log requirement.
- `screenshots/user_login_clears_stale_guid.png`: rendered proof of the T-001
  account-switch stale GUID guard.
- `video/user_login_clears_stale_guid_proof.mp4`: 4.5-second proof video for
  the same RED / CHANGE / GREEN flow.

## Result

- Final disposition: passed for the bounded T-001 local slice. Android/iOS Auth0
  account-switch smoke evidence remains the production closure gate.
