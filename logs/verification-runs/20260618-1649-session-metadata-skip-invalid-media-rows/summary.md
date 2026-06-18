# Evidence Run: Skip invalid stored media rows during session metadata load

- Source: docs/control/backlog-import.md#row-35-use-guids-everywhere-across-controllers-views
- Slug: `session-metadata-skip-invalid-media-rows`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Historical session metadata loads valid media even when one stored media row is malformed
- [ ] Invalid stored photo/video rows are logged and skipped without replacing the active session

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
