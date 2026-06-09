# Evidence Run: HydraCam API URI construction cleanup

- Source: docs/control/backlog-import.md#row-106-api-contract-cleanup
- Slug: `api-uri-construction-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] GET and POST API helpers build URIs through one shared path instead of whitespace-stripping string concatenation
- [x] Endpoint query values preserve spaces and special characters through Uri query encoding
- [x] Existing upload and user API contract tests keep passing

## Device Matrix

- Flutter unit test runner; macOS host; identifier:
  `hydracamv2-local-tests`; role: `api-uri-contract-regression`.

## Evidence

- Red test: `flutter test test/services/hydracam_api_service_test.dart`
  failed because `fetchCourts()` and `endSession()` lost spaces and decoded
  `+` characters in query values while building request URIs.
- Focused green: `flutter test test/services/hydracam_api_service_test.dart`
  passed after centralizing endpoint and base-URI construction.
- Repo gates after implementation: `git diff --check`, `flutter analyze
  --no-pub`, and full `flutter test` passed.
- Command output is captured in `commands.log`.

## Result

- Final disposition: passed.
- `hydracamApiEndpoint()` now builds relative API endpoints with `Uri`
  query-parameter encoding, and `HydraCamApiService._apiUri()` joins those
  endpoints to the shared API base URL.
- GET, POST, create-session, end-session, upload-media, and user lookup paths
  now use the shared URI construction path instead of whitespace-stripping
  string concatenation.
- Limitation: this is a tier D mock-HTTP service proof. Backend contract
  coordination and server-side hardcoded field cleanup remain open.
