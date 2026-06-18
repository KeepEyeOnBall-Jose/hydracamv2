# Evidence Run: Clear malformed master-side slave session diagnostics

- Source: docs/control/backlog-import.md#2-preserve-session-state-across-master-reconnect
- Slug: `master-malformed-reported-session-guid`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Master heartbeat ignores non-string reported sessionGuid values
- [x] Malformed reported sessionGuid clears stale slave session media diagnostics

## Device Matrix

- Not applicable. Tier D unit coverage for master-side connected-client
  heartbeat diagnostics.

## Evidence

- Red/green regression test:
  `flutter test --no-pub test/master/master_network_snapshot_cache_test.dart`
  first failed because a malformed heartbeat `sessionGuid` cast aborted the
  update and left stale `reportedSessionGuid` / `sessionMedia`, then passed
  after reported session GUID normalization became strict string-only.
- Broader checks passed:
  `flutter test --no-pub test/master`,
  `flutter analyze --no-pub`,
  `git diff --check`, and `flutter test --no-pub`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. Malformed non-string slave session reports now
  clear stale master-side session/media diagnostics instead of preserving an
  old reported session.
