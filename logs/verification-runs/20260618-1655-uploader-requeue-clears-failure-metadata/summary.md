# Evidence Run: Persist cleared upload failure reason when requeueing media

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `uploader-requeue-clears-failure-metadata`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Retrying a failed or cancelled media item clears uploadFailureReason in persisted metadata
- [ ] Requeued media remains pending and auto-upload disabled behavior stays unchanged

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
