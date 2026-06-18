# Evidence Run: Clear stale slave session-media diagnostics

- Source: docs/control/backlog-import.md#2-preserve-session-state-across-master-reconnect
- Slug: `stale-session-media-diagnostics`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Master connected-client diagnostics clear a slave sessionMedia summary when the same slave no longer reports an active session
- [x] Existing session-media heartbeat diagnostics remain preserved while a slave reports the active session

## Device Matrix

- Tier D service/model validation only; no device under test was required.
- `adb devices -l` reported no attached Android devices.
- `flutter devices --device-timeout 10` did not return during wireless iOS
  discovery and was interrupted; this did not block the unit/integration scope.

## Evidence

- `commands.log` records the baseline focused test passing before the new
  regression was added.
- The corrected red regression failed against the previous behavior with
  `Expected: null` and an actual stale `sessionMedia` map containing
  `photoCount`, `videoCount`, `pendingUploadCount`, and `uploadedCount`.
- After the fix, the focused regression, full
  `test/master/master_network_snapshot_cache_test.dart`, related
  master/slave diagnostics tests, focused analyzer, full analyzer, and full
  Flutter test suite passed.

## Result

- Final disposition: passed. `MasterServer` now clears cached slave
  `sessionMedia` diagnostics when the same slave no longer reports a nonblank
  active session GUID, while preserving the summary for active reported
  sessions.
