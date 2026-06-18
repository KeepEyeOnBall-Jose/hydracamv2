# Uploader Cancel Resumes Queue

- Status: `passed`
- Date: `2026-06-18`
- Control-plane item: `docs/control/backlog-import.md` section `Improve upload failure, cancel, requeue, and progress UI`
- Scope: service-level regression for active upload cancellation with additional queued media.

## What Changed

- Added a regression proving that cancelling the current upload does not strand the remaining queue in the same manual upload drain.
- Updated `UploaderService` so reset remains a hard stop, while an active upload cancellation can resume the existing queue after the stale HTTP completion is ignored.

## Validation

```bash
flutter test --no-pub test/services/uploader_service_test.dart --plain-name 'cancelCurrentUpload continues draining queued media'
flutter test --no-pub test/services/uploader_service_test.dart
flutter analyze --no-pub lib/services/uploader_service.dart test/services/uploader_service_test.dart
flutter test --no-pub
```

All commands passed.

## Notes

- This is pure shared service logic; no hardware proof is required for the service-level regression.
- Existing untracked historical evidence directories were left unstaged.
