# Evidence Run: Assert storage forced-stop callback failure logging

- Source: docs/control/backlog-import.md#5-add-critical-battery-autostop
- Slug: `storage-critical-callback-log-test-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] StorageService critical callback failure coverage asserts the LogService diagnostic
- [x] Focused storage service tests and analyzer pass after the test cleanup

## Device Matrix

- Not applicable. This was a Tier D test-harness cleanup with no runtime or
  device-facing behavior change.

## Evidence

- Baseline focused test before editing passed:
  `flutter test --no-pub test/services/storage_service_test.dart`.
- Post-edit focused test passed:
  `flutter test --no-pub test/services/storage_service_test.dart`.
- Static validation passed: `flutter analyze --no-pub`.
- Whitespace validation passed: `git diff --check`.
- `test/services/storage_service_test.dart` now drains the guarded critical
  storage callback and asserts `LogService` records the callback failure
  diagnostic.

## Result

- Final disposition: passed. This strengthens local regression coverage for the
  storage critical-callback failure path while preserving the open hardware
  requirement for platform battery/storage event proof.
