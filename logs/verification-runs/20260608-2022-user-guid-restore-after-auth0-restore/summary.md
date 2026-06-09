# Evidence Run: Board item 11: Make mobile Auth0 login recoverable and release-safe

- Source: docs/control/backlog-import.md
- Slug: `user-guid-restore-after-auth0-restore`
- Verification tier: C (multi-device-emulated-cluster)
- Status: prepared

## Acceptance Checks

- [ ] UserService restores a saved Auth0 session at startup, re-fetches the HydraCam backend user GUID from the restored email, and clears login state when restore fails.

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
