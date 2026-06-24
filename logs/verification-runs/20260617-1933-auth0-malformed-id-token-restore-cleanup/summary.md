# Evidence Run: Reject malformed stored Auth0 credentials without restoring partial state

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `auth0-malformed-id-token-restore-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Startup restore returns false for malformed stored ID tokens instead of throwing
- [ ] Malformed stored credentials are cleared from secure storage and in-memory AuthService state

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
