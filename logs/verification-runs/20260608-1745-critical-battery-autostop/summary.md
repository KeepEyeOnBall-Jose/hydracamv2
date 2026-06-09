# Evidence Run: Add critical battery autostop

- Source: docs/control/backlog-import.md#5-add-critical-battery-autostop
- Slug: `critical-battery-autostop`
- Verification tier: B (emulator-simulator-e2e)
- Status: partial

## Acceptance Checks

- [x] Critical battery during recording triggers a safe stop callback exactly once per critical event
- [x] The user sees a meaningful critical-battery message
- [x] Battery autostop writes a LogService entry
- [x] Non-critical low-battery warnings remain throttled

## Device Matrix

- `flutter-test`: macOS Flutter widget test runner, simulated app surface for
  `BatteryService` snackbar/autostop behavior.

## Evidence

- Screenshot: `screenshots/critical_battery_snackbar.png`
- Video: `video/critical_battery_snackbar_proof.mp4`
- Device/test log: `device-logs/flutter-widget-runner.log`
- Commands: `commands.log`
- RED proof: focused tests first failed because `criticalBatteryThreshold`,
  `onCriticalBatteryCallback`, and `forceStopRecordingDueToBattery` did not
  exist.
- GREEN proof: focused battery/camera tests pass after implementation.
- Analyzer: `flutter analyze --no-pub` passes.

## Result

- Final disposition: partially completed. Code and simulated visual proof are
  in place for the critical-battery autostop path. Keep the existing board item
  open until a real-device or emulator recording run proves the platform
  battery event stops an active recording and captures device logs.
