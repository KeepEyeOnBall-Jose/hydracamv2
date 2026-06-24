# Evidence Run: Abort in-flight upload transport when uploader resets for session isolation

- Source: docs/control/backlog-import.md#3-prevent-stale-uploads-from-crossing-sessions
- Slug: `uploader-reset-cancels-transport`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] UploaderService.reset closes the active API client while an upload request is in flight
- [ ] Stale upload completion remains ignored after reset

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
