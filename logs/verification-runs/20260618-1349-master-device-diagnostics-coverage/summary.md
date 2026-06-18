# Evidence Run: Lock master connected-device diagnostics coverage

- Source: docs/control/backlog-import.md#6-make-networkdevice-identity-visible
- Slug: `master-device-diagnostics-coverage`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Focused MasterServer coverage proves slave app/hardware registration,
  heartbeat session media, stale-session capture filtering, identify
  acknowledgement diagnostics, disconnected identify state, and disconnected
  preview labels; analyzer and full Flutter tests pass.

## Device Matrix

- macOS host, macOS 26.4.1, `macos`, local Flutter test host.
- No real LAN master/slave smoke was run; this pack is focused MasterServer
  diagnostics coverage.

## Evidence

- `commands.log` records:
  - `flutter test --no-pub test/master/master_network_snapshot_cache_test.dart`
  - `flutter analyze --no-pub`
  - `flutter test --no-pub`

## Result

- Final disposition: passed for local/static/Tier D validation. Real-device
  network smoke evidence remains open for item 6.
