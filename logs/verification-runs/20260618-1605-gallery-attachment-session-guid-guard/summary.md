# Evidence Run: Reject stale gallery attachment session GUIDs

- Source: docs/control/backlog-import.md#9-improve-old-media-gallery-session-attachment
- Slug: `gallery-attachment-session-guid-guard`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Gallery attachment service rejects stale or mismatched session GUIDs before copying media
- [x] Focused gallery attachment tests and analyzer pass after the guard

## Device Matrix

- Not applicable. This was a Tier D service/widget regression with no runtime
  device requirement.

## Evidence

- Baseline focused service test passed before adding the new regression:
  `flutter test --no-pub test/services/gallery_session_attachment_service_test.dart`.
- Red check failed after adding
  `attachImportedMedia rejects stale session guid before copying`; the current
  implementation copied media into `session_stale-gallery-guid` and registered
  it on active session `active-gallery-guid`.
- Green check passed after guarding `attachImportedMedia()`:
  `flutter test --no-pub test/services/gallery_session_attachment_service_test.dart`.
- Focused service/widget validation passed:
  `flutter test --no-pub test/services/gallery_session_attachment_service_test.dart
  test/widgets/add_gallery_media_button_test.dart`.
- Static validation passed: `flutter analyze --no-pub`.
- Whitespace validation passed: `git diff --check`.

## Result

- Final disposition: passed. Stale gallery import calls now return before
  session-directory creation, media copy, uploader registration, or active
  session metadata mutation.
