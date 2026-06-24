# Evidence Run: Reject blank stored Auth0 token fields during restore

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `auth0-blank-stored-token-guards`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] AuthService.restoreStoredSession does not restore whitespace-only access tokens
- [ ] AuthService.restoreStoredSession does not call token refresh with a whitespace-only refresh token

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
