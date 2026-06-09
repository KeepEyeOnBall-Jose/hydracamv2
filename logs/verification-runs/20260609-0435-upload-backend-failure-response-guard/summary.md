# Evidence Run: T-016. Photo/video upload API backend response-shape guard

- Source: docs/control/backlog-import.md#testing-issue-candidates
- Slug: `upload-backend-failure-response-guard`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] uploadMedia rejects HTTP 200 backend bodies that explicitly report upload failure
- [x] uploadMedia preserves existing empty-body HTTP 200 success behavior
- [x] Focused HydraCam API service tests pass

## Device Matrix

- Flutter HydraCam API service unit-test runner; macOS test host;
  verification role.

## Evidence

- `dart format lib/services/hydracam_api_service.dart
  test/services/hydracam_api_service_test.dart` passed.
- Source search recorded `_uploadResponseReportsFailure()` and the focused
  backend-failure-body regression.
- `flutter test --no-pub test/services/hydracam_api_service_test.dart` passed.

## Result

- Final disposition: passed for local backend upload response-shape coverage;
  broader corrupt-file and live backend API-contract proof remains open.
