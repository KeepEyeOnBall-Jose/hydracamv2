# Evidence Run: Reject malformed inbound media before persistence

- Source: docs/control/backlog-import.md#2-preserve-captured-materials-through-reconnect
- Slug: `malformed-inbound-media-preflight`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Malformed inbound photo timestamps do not add media to the master session
- [x] Malformed inbound photo timestamps do not write received media files or gallery artifacts

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Recorded a red focused master test proving malformed inbound photo
  timestamps were detected only after received-media persistence, then reran
  the focused master file, `flutter test --no-pub test/master`,
  `flutter analyze --no-pub`, `git diff --check`, and full
  `flutter test --no-pub`.

## Result

- Final disposition: passed
