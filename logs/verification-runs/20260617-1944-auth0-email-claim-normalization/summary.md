# Evidence Run: Normalize Auth0 email claims before storing auth state

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `auth0-email-claim-normalization`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] AuthService.login exposes trimmed Auth0 email claims
- [ ] AuthService.restoreStoredSession exposes trimmed stored Auth0 email claims

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
