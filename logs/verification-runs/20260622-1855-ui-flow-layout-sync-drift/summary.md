# Evidence Run: Tighten existing UI flow and layout drift

- Source: docs/control/status-and-roadmap.md#default-priority-queue
- Slug: `ui-flow-layout-sync-drift`
- Verification tier: B (emulator-simulator-e2e)
- Status: partially blocked

## Acceptance Checks

- [x] Main/master screen uses consistent compact action sizing without overflow on common phone layouts
- [x] Court selection supports a clearer center-first and court-first flow with search that preserves selection
- [x] Slave screen fits a Samsung S10e-sized landscape viewport without Flutter overflow
- [x] Slave clock sync refreshes often enough to avoid stale/desynced status between master time-sync messages

## Device Matrix

- Android emulator `emulator-5554`, Android 14 API 34, UI validation target:
  visible at baseline, later relaunched for landscape proof.
- iPhone 16 Pro simulator `6A2E7E6A-05F8-47D6-88AE-85E3434AC6D3`, iOS 18.4
  simulator, UI validation target.
- Physical S10e hardware: not visible in final `adb devices -l`; S10e behavior
  was covered by widget tests at `Size(760, 360)`.

## Evidence

- `commands.log` records baseline `git status`, `flutter devices`, `adb devices`,
  focused widget/service tests, analyzer, `git diff --check`, and final ADB
  inventory.
- Focused tests passed through the evidence wrapper:
  `flutter test --no-pub test/widgets/court_selection_widget_test.dart
  test/master/master_screen_test.dart test/slave/slave_screen_fast_connect_test.dart
  test/services/time_sync_service_test.dart test/slave/slave_client_time_sync_test.dart
  test/slave/slave_screen_sync_chip_test.dart`.
- `flutter analyze --no-pub` passed.
- `git diff --check` passed.
- Initial screenshot/logcat artifact capture was attempted after the tests, but
  ADB no longer saw `emulator-5554`; zero-byte placeholders from the failed
  capture were removed.
- Follow-up emulator proof after the compact top-panel trim is recorded in
  `logs/verification-runs/20260622-1934-ui-flow-layout-sync-emulator-slave-screen-landscape-after-trim/`.
  That run rebuilt and installed the current APK, switched the running app from
  automation standby into the actual `SlaveScreen`, captured a landscape
  `866 x 388` screenshot, and found no Flutter overflow markers in logcat.

## Result

- Final disposition: code/test validation and Android-emulator landscape proof
  passed; physical S10e artifact capture remains blocked by no ADB-visible
  Android/S10e target at final inventory.
