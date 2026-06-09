# Evidence Run: Uploader enqueue async return cleanup

- Source: lib/services/uploader_service.dart#addMediaToQueue-async-void
- Slug: `uploader-enqueue-async-return-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] addMediaToQueue returns an awaitable Future so callers can wait for settings-driven enqueue side effects
- [x] Existing duplicate/current-upload guards remain unchanged
- [x] Focused uploader service tests prove awaitable enqueue, duplicate guard, and current-upload guard paths

## Device Matrix

- MacBook host, macOS 26.4.1 arm64, unit-test runner.

## Evidence

- Red test: `flutter test test/services/uploader_service_test.dart` failed to
  compile because `await uploaderService.addMediaToQueue(photo)` used an
  expression with static type `void`.
- Green focused tests: `flutter test test/services/uploader_service_test.dart`
  passed after `addMediaToQueue` returned `Future<void>` and direct test call
  sites awaited enqueue completion.
- Supporting focused tests: `flutter test
  test/slave/slave_client_registration_test.dart` passed after the
  start-upload-all setup awaited enqueue completion.
- Repo gates passed: `git diff --check`, `flutter analyze --no-pub`, and full
  `flutter test`.

## Result

- Final disposition: uploader enqueue is awaitable without changing the
  duplicate queued-media or current-upload guards.
