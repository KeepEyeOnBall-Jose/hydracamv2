# Evidence Run: Reject inbound stale-session slave media

- Source: docs/control/backlog-import.md#2-preserve-captured-materials-through-reconnect
- Slug: `inbound-stale-session-media-guard`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Inbound photo media from a slave reporting a different active session is not saved to the master session
- [x] Inbound media from a matching or unreported session remains accepted

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Recorded a red focused master test proving stale-session inbound photo media
  was previously saved into the current master session, then reran the focused
  master file, `flutter test --no-pub test/master`, `flutter analyze --no-pub`,
  `git diff --check`, and full `flutter test --no-pub`.

## Result

- Final disposition: passed
