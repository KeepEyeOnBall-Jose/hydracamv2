# Evidence Run: Session details async handler cleanup

- Source: cleanup scan: async void screen handlers
- Slug: `session-details-async-handler-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] SessionDetails load-session and upload-confirm paths are covered by widget tests
- [ ] SessionDetails async handlers return Future<void> and are dispatched explicitly from UI callbacks
- [ ] Focused screen tests, analyzer, diff check, and full Flutter tests pass

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
