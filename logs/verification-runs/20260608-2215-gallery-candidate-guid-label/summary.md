# Evidence Run: JAVI row 35: Candidate session labels prefer GUIDs

- Source: docs/control/backlog-import.md
- Slug: `gallery-candidate-guid-label`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Gallery candidate session labels prefer session GUIDs over legacy session IDs, with session ID only as a fallback.

## Device Matrix

- MediaSelection widget test runner, macOS host / Flutter test, role
  `gallery-session-guid`, identifier `MediaSelectionScreen candidate GUID
  label`.

## Evidence

- `device-logs/red-tests.log`: focused widget test failed before the code
  change because the video tile did not show `Candidate: guid-court-1`.
- `device-logs/green-focused-tests.log`: focused widget tests passed after the
  change, covering GUID preference and legacy session-ID fallback.
- `screenshots/gallery_candidate_guid_label.png`: rendered visual proof of the
  before/after label behavior and fallback text.
- `video/gallery_candidate_guid_label_proof.mp4`: 4.5-second proof video
  showing the same row 35 slice.

## Result

- Final disposition: passed for the bounded row 35 slice. Keep row 35 open for
  the broader controllers/views GUID audit and real old-media attachment smoke
  evidence.
