# Evidence Run: Block capture writes without active service session

- Source: docs/control/backlog-import.md#0-asap-validate-camera-lens-and-video-profile-settings-on-iphonesamsung
- Slug: `camera-block-session-null-capture`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] CameraService refuses mock photo capture when no active session exists
- [x] CameraService refuses mock video save when no active session exists
- [x] No session_null media directory is created by refused capture paths

## Device Matrix

- Not applicable. Tier D service coverage for the shared camera media path.

## Evidence

- Red/green regression test:
  `flutter test --no-pub test/services/camera_service_failure_test.dart` first
  failed after writing
  `camera_service_mock_docs.../session_null/mock_...jpg`, then passed after
  `_getSessionMediaPath()` required a nonblank active service session GUID.
- Broader checks passed:
  `flutter test --no-pub test/services/camera_service_failure_test.dart test/services/session_manager_test.dart`,
  `flutter analyze --no-pub`,
  `git diff --check`, and `flutter test --no-pub`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. Camera media writes now fail before creating
  `session_null` directories when no active service session exists.
