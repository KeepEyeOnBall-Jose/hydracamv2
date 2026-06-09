# Evidence Run: T-016. Photo/video upload API invalid-file guard

- Source: docs/control/backlog-import.md#testing-issue-candidates
- Slug: `upload-empty-file-guard`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] uploadMedia rejects zero-byte local media files before HTTP send
- [x] uploadMedia keeps existing valid photo/video multipart behavior green
- [x] Focused HydraCam API service tests pass

## Device Matrix

- Flutter HydraCam API service unit-test runner; macOS test host;
  verification role.

## Evidence

- `dart format lib/services/hydracam_api_service.dart
  test/services/hydracam_api_service_test.dart` passed.
- Source search recorded the zero-byte guard and focused regression test.
- `flutter test --no-pub test/services/hydracam_api_service_test.dart` passed.

## Result

- Final disposition: passed for local zero-byte invalid-upload coverage; broader
  backend response-shape/corrupt-file API-contract proof remains open.
