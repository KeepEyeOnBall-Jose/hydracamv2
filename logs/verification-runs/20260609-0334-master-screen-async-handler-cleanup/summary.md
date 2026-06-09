# Evidence Run: Master screen async handler cleanup

- Source: cleanup scan: final MasterScreen async void handlers
- Slug: `master-screen-async-handler-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] MasterScreen start-session button creates a backend session through the mocked API
- [ ] MasterScreen recording start path opens the master video preview with mocked camera services
- [ ] MasterScreen async handlers return Future<void> and UI callbacks dispatch them explicitly
- [ ] Focused MasterScreen tests, analyzer, diff check, and full Flutter tests pass

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
