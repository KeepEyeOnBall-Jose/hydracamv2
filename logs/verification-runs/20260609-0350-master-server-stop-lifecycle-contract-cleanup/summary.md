# Evidence Run: Master server stop lifecycle contract cleanup

- Source: cleanup scan: MasterServer.stopServer session-ending TODO
- Slug: `master-server-stop-lifecycle-contract-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] MasterServer.stopServer is documented and tested as transport cleanup only
- [ ] Explicit MasterServer.endCurrentSession remains the only server-side session-ending path
- [ ] Focused MasterServer tests, analyzer, diff check, and full Flutter tests pass

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
