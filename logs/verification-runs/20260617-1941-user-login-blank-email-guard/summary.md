# Evidence Run: Reject blank Auth0 login email before HydraCam user lookup

- Source: docs/control/backlog-import.md#11-make-mobile-auth0-login-recoverable-and-release-safe
- Slug: `user-login-blank-email-guard`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] UserService.login rejects blank Auth0 email values
- [ ] Blank login emails do not trigger HydraCam GUID lookup or mark the user logged in

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
