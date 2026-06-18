# Evidence Run: Ignore stale slave session-ended commands

- Source: docs/control/status-and-roadmap.md#multi-device-synchronization-evidence
- Slug: `stale-session-ended-preserves-slave-session`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] A slave with an active different session ignores a sessionEnded payload for another master session
- [x] Ending a master session broadcasts sessionEnded with the ended session GUID

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Recorded red failures for the slave stale-session `sessionEnded` regression
  and the master broadcast payload regression, then reran the focused slave and
  master files, `flutter test --no-pub test/master test/slave`,
  `flutter analyze --no-pub`, `git diff --check`, and full
  `flutter test --no-pub`.

## Result

- Final disposition: passed
