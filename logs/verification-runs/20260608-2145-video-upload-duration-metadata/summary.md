# Evidence Run: Backlog row 17: Video upload duration metadata

- Source: docs/control/backlog-import.md
- Slug: `video-upload-duration-metadata`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Video uploads include recording end timestamp and computed duration metadata while photo uploads remain unchanged.

## Device Matrix

- Mock HTTP multipart upload; macOS host / Flutter test; identifier:
  `HydraCamApiService video metadata fields`; role: upload-metadata.

## Evidence

- `device-logs/red-tests.log` captured the missing video metadata contract.
- `device-logs/green-focused-tests.log` captured the focused passing
  multipart upload tests.
- `screenshots/video_upload_duration_metadata.png` summarizes the TDD proof.
- `video/video_upload_duration_metadata_proof.mp4` provides a 4.5 second
  proof video.

## Result

- Final disposition: passed for the mobile upload metadata slice. This does
  not claim backend duration rendering is fixed.
