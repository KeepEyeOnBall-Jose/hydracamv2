# Evidence Run: FALLOS Y MEJORAS row 43

- Source: docs/control/backlog-import.md row 43
- Slug: `scheduled-task-past-due-replacement-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] ScheduledTaskService cancels and settles any same-id pending task before executing a past-due replacement, preventing stale timers from remaining registered

## Device Matrix

- Dart/Flutter unit test surface on macOS host runtime.
- Fixed-clock `ScheduledTaskService` instance with corrected-time offsets.
- No physical device required for this Tier D scheduler cleanup.

## Evidence

- `commands/flutter-test-test-services-scheduled-task-service-test-dart/command.txt`
  captures `flutter test test/services/scheduled_task_service_test.dart`.
- `commands/flutter-test-test-services-scheduled-task-service-test-dart/stdout.txt`
  records `+6: All tests passed!`.
- Regression test first failed because the stale same-ID task future did not
  complete when replaced by a past-due task, then passed after same-ID
  cancellation moved before immediate execution.

## Result

- Final disposition: local scheduler cleanup passed. Row 43 remains open for
  real-device clock-offset estimation and capture-start skew evidence.
