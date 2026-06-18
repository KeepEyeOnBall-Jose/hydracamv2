# Master Time-Sync Clock Injection

- Status: `passed`
- Date: `2026-06-18`
- Control-plane item: `docs/control/backlog-import.md` section `Support synchronized time accurately enough for capture`
- Scope: deterministic master time-sync response coverage.

## What Changed

- Added an injectable master clock to `MasterServer` for the `timeSyncResponse`
  receive/send timestamps.
- Added focused coverage proving `timeSyncResponse.t1` and `timeSyncResponse.t2`
  use the injected master clock, so offset/skew tests no longer depend on wall
  clock timing.

## Validation

```bash
flutter test --no-pub test/master/master_time_sync_test.dart
flutter test --no-pub test/services/time_sync_service_test.dart test/slave/slave_client_time_sync_test.dart test/integration/two_device_sync_capture_test.dart
flutter analyze --no-pub lib/master/master_server.dart test/master/master_time_sync_test.dart
flutter analyze --no-pub
flutter test --no-pub
```

All commands passed.

## Notes

- This is a shared timing refactor/test slice; no hardware proof is claimed here.
- The remaining control-plane work is real-device offset estimation and capture
  start-skew evidence.
- Flutter commands were run serially after a parallel invocation hit the
  native-assets startup lock race.
