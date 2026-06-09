# Evidence Run: scheduled-task-callback-cleanup

- Source: lib/services/scheduled_task_service.dart#scheduleTask
- Slug: `scheduled-task-future-callback-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] ScheduledTaskService.scheduleTask exposes a typed awaitable Future for async callbacks
- [x] Immediate past-due scheduled callbacks can be awaited through completion
- [x] Focused scheduled/slave tests plus repo gates pass

## Device Matrix

- MacBook host, macOS 26.4.1 arm64, unit-test runner.

## Evidence

- Red test: `flutter test test/services/scheduled_task_service_test.dart`
  failed to compile when the new regression awaited
  `ScheduledTaskService.scheduleTask()`, because the method still returned
  `void`.
- Green focused tests: `flutter test
  test/services/scheduled_task_service_test.dart
  test/slave/slave_client_registration_test.dart` passed after
  `scheduleTask()` returned `Future<void>` and accepted
  `FutureOr<void> Function()` callbacks.
- Repo gates: `git diff --check`, `flutter analyze --no-pub`, and full
  `flutter test` passed.

## Result

- Final disposition: scheduled task callbacks now have a typed, awaitable
  service contract for immediate and timer-driven async command execution.
