# Evidence Run: Propagate upload backend failure details into media state

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `uploader-backend-failure-reason-detail`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] UploaderService stores a bounded backend upload failure reason on failed media
- [ ] Focused uploader and API service tests pass after the failure-detail propagation

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
