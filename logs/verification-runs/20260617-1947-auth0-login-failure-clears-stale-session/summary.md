# Evidence Run: Clear stale Auth0 session when interactive login fails

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `auth0-login-failure-clears-stale-session`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] AuthService.login clears in-memory Auth0 state when the AppAuth login call throws
- [ ] AuthService.login clears stored credentials when the AppAuth login call throws

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
