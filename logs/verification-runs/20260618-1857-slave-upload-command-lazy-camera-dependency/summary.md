# Evidence Run: Remove hidden camera singleton dependency from upload-only slave command

- Source: logs/verification-runs/20260618-1851-store-readiness-mode-scope/commands.log#startUploadingAll-isolated-failure
- Slug: `slave-upload-command-lazy-camera-dependency`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] startUploadingAll slave command test passes when run in isolation
- [x] SlaveClient construction no longer requires CameraServiceSingleton for non-camera commands
- [x] Focused slave client tests and analyzer pass

## Device Matrix

- Not required for tier D unit/socket coverage.

## Evidence

- Green isolated regression: `flutter test --no-pub test/slave/slave_client_registration_test.dart --plain-name "startUploadingAll command starts pending upload queue"` passed after lazy camera resolution.
- Focused slave registration file: `flutter test --no-pub test/slave/slave_client_registration_test.dart` passed.
- Focused slave time-sync file: `flutter test --no-pub test/slave/slave_client_time_sync_test.dart` passed.
- Analyzer: `flutter analyze --no-pub` passed.
- Full suite: `flutter test --no-pub` passed.
- Diff hygiene: `git diff --check` passed.
- Note: the combined registration/time-sync command exposed an existing test cleanup race (`Cannot add new events after calling close`), but both files pass independently and the full suite passes.

## Result

- Final disposition: passed. `SlaveClient` now resolves `CameraService` lazily so upload-only commands can run without pre-initializing `CameraServiceSingleton`.
