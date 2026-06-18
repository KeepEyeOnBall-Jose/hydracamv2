# Evidence Run: Ignore non-string Auth0 picture claims during restore

- Source: docs/control/backlog-import.md#T-001-auth0-login-startup-restore-android-process-death-recovery-logout-and-account-switch-regression-tests
- Slug: `auth0-restore-nonstring-picture-claim`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Stored credentials with a valid email and non-string optional picture restore without throwing
- [ ] Profile picture is null when the ID token picture claim is not a string

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
