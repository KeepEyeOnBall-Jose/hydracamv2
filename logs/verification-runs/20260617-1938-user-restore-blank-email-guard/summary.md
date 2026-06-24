# Evidence Run: Reject blank restored Auth0 email before HydraCam user lookup

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `user-restore-blank-email-guard`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] UserService.restoreStoredSession returns false when Auth0 restore exposes a blank email
- [ ] Blank restored emails do not trigger a HydraCam GUID lookup or mark the user logged in

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
