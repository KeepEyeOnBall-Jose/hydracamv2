# Evidence Run: Support synchronized time accurately enough for capture

- Source: docs/control/backlog-import.md#7-support-synchronized-time-accurately-enough-for-capture
- Slug: `scheduled-task-clock-offset`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] ScheduledTaskService stores an explicit clock offset
- [x] Scheduling delay is computed from corrected local time
- [x] Slave scheduled commands use the corrected-clock scheduling service
- [x] Screenshot and video proof show the corrected delay behavior

## Device Matrix

- `flutter-test`: macOS Flutter unit-test runner for corrected scheduling logic.

## Evidence

- RED proof: `flutter test --no-pub test/services/scheduled_task_service_test.dart`
  failed because the offset-aware scheduler API did not exist.
- GREEN proof: focused scheduler tests pass after adding explicit clock offset,
  corrected-now delay math, immediate past-time execution, and cancellable
  future timers.
- Integration surface: `SlaveClient` scheduled-command execution now uses
  `ScheduledTaskService.instance.delayUntil()` and `scheduleTask()`.
- Full suite: `flutter test --no-pub` passes.
- Analyzer: `flutter analyze --no-pub` passes.
- Screenshot: `screenshots/scheduled_task_clock_offset.png`
- Video: `video/scheduled_task_clock_offset_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. The app now has a corrected-clock
  scheduling primitive and slave commands route through it. Keep item 7 open
  for real clock-offset estimation/exchange and measured multi-device
  capture-start skew evidence.
