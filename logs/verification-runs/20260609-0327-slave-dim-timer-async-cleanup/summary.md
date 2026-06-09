# Evidence Run: Slave dim timer async cleanup

- Source: cleanup scan: async void slave screen handlers
- Slug: `slave-dim-timer-async-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] SlaveScreen dims during recording when screen auto-off is enabled and wakes on tap
- [ ] Dim timer helpers return Future<void>, dispatch explicitly, and guard mounted state
- [ ] Focused slave screen test, analyzer, diff check, and full Flutter tests pass

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
