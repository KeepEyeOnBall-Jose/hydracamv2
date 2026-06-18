# Evidence Run: Reject invalid upload session GUIDs

- Source: docs/control/backlog-import.md#t-016-photo-video-upload-api-test-with-invalid-files
- Slug: `reject-invalid-upload-session-guids`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] uploadMedia rejects blank session GUIDs before HTTP send
- [x] uploadMedia rejects sentinel session GUIDs before HTTP send
- [x] uploadMedia still accepts valid service session GUIDs

## Device Matrix

- Not applicable. Tier D upload API contract coverage.

## Evidence

- Red/green regression test: `flutter test --no-pub
  test/services/hydracam_api_service_test.dart` first failed because blank and
  sentinel session GUID uploads were sent and reported successful, then passed
  after upload session GUID validation was moved ahead of file/header/token/HTTP
  work.
- Broader checks passed: `flutter analyze --no-pub`, `flutter test --no-pub`,
  and `git diff --check`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. Invalid upload session GUIDs now fail before
  network work, while valid service-session upload tests remain green.
