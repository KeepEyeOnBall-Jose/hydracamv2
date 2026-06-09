# Evidence Run: Master scheduled command dispatch cleanup

- Source: lib/master/master_server.dart#scheduleCommand-targeted-broadcast-fallback
- Slug: `master-scheduled-command-dispatch-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Scheduled commands for missing slave IDs do not broadcast to all connected slaves
- [x] scheduleCommand uses the same eligible-client dispatcher as sendCommand and sendCommandToAll
- [x] Focused tests prove scheduled missing, scheduled connected, and scheduled broadcast paths

## Device Matrix

- MacBook host, macOS 26.4.1 arm64, unit-test runner.

## Evidence

- Red test: `flutter test test/master/master_network_snapshot_cache_test.dart`
  failed because `scheduleCommand("takePhoto", ..., deviceId:
  "missing-slave")` broadcast the scheduled payload to both registered mock
  slave sockets.
- Green focused test: `flutter test
  test/master/master_network_snapshot_cache_test.dart` passed after
  `scheduleCommand` encoded the scheduled payload once and sent it through
  `_sendCommandToEligibleClients` for both targeted and broadcast paths.
- Repo gates passed: `git diff --check`, `flutter analyze --no-pub`, and full
  `flutter test`.

## Result

- Final disposition: scheduled command dispatch no longer falls back to
  broadcast when a non-null slave ID is missing; scheduled connected and
  scheduled broadcast paths remain covered by focused tests.
