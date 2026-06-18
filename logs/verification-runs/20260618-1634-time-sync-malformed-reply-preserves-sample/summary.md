# Evidence Run: Ignore malformed time-sync replies without consuming pending samples

- Source: docs/control/backlog-import.md#7-support-synchronized-time-accurately-enough-for-capture
- Slug: `time-sync-malformed-reply-preserves-sample`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Malformed timeSyncResponse replies do not remove the matching pending request
- [ ] A later valid reply for the same id can still produce a calibration sample

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
