# Evidence Run: Reject media adds without active session

- Source: docs/control/backlog-import.md#2-preserve-session-state-across-master-reconnect
- Slug: `session-manager-reject-inactive-media`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] SessionManager.addPhoto rejects when no active session exists
- [x] SessionManager.addVideo rejects when no active session exists
- [x] Rejected inactive-session media is not queued for upload

## Device Matrix

- Not applicable. Tier D service coverage for session/media invariants.

## Evidence

- Red/green regression test:
  `flutter test --no-pub test/services/session_manager_test.dart` first failed
  because inactive-session `addPhoto()` / `addVideo()` completed instead of
  throwing, then passed after both methods required an active session before
  mutation, metadata writes, sync sidecars, or upload enqueue.
- Broader checks passed:
  `flutter test --no-pub test/services/session_manager_test.dart test/services/camera_service_failure_test.dart test/services/uploader_service_test.dart`,
  `flutter analyze --no-pub`,
  `git diff --check`, and `flutter test --no-pub`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. Captured media cannot enter session metadata or
  the uploader queue without an active service session.
