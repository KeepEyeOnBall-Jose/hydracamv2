# Evidence Run: Row 35/T-020: GUID cleanup and upload estimate refinement

- Source: docs/control/backlog-import.md#open-rows-from-javi-immediate-backlog
- Slug: `guid-api-upload-estimate-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Session display and load paths prefer `sessionGuid` and fall back to
      `sessionId` for legacy metadata.
- [x] User API endpoints and email query key are centralized in
      `HydraCamApiService`.
- [x] `UploaderService` keeps sub-second completed upload samples when
      estimating queued upload time.

## Device Matrix

- Flutter unit/widget test runner, macOS host, role
  `model-api-upload-regression`, identifier `hydracamv2-local-tests`.

## Evidence

- `commands.log`: focused RED/GREEN-related command transcript for the final
  test bundle plus analyzer. The pack also records the analyzer lint failures
  found after the first implementation pass and the final clean analyzer run.
- Focused tests covered:
  `test/models/capture_session_test.dart`,
  `test/screens/session_details_screen_test.dart`,
  `test/screens/media_selection_screen_test.dart`,
  `test/services/gallery_session_candidate_source_test.dart`,
  `test/services/hydracam_api_service_test.dart`,
  `test/services/user_service_test.dart`, and
  `test/services/uploader_service_test.dart`.
- No simulator/device screenshots, video, or device logs were captured for this
  bounded Tier D cleanup slice. Keep real gallery/session UI and upload
  telemetry closure gated on the existing higher-tier backlog items.

## Result

- Final disposition: passed for the bounded local cleanup/refactor slice.
  Remaining related work is larger: real old-media attachment smoke evidence,
  backend/API contract coordination, and real-device upload telemetry.
