# Evidence Run: Camera forced-stop helper cleanup

- Source: cleanup scan: duplicate storage/battery forced-stop recording paths
- Slug: `camera-forced-stop-helper-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Storage and battery forced-stop paths share one helper without changing user-visible notifications
- [ ] Focused camera-service tests prove mock recording stops, interruption flag flips, and captured video is persisted
- [ ] Analyzer, diff check, and full Flutter tests pass

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
