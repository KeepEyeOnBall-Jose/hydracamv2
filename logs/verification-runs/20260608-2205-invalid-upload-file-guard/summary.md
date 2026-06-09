# Evidence Run: Testing T-016: Invalid upload file guard

- Source: docs/control/backlog-import.md
- Slug: `invalid-upload-file-guard`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Upload API returns false for a missing media file with a clear file-missing log and without sending an HTTP multipart request.

## Device Matrix

- Mock HTTP upload API; macOS host / Flutter test; identifier:
  `HydraCamApiService missing file guard`; role: invalid-upload-file.

## Evidence

- `device-logs/red-tests.log` captured the generic PathNotFoundException
  behavior before the guard.
- `device-logs/green-focused-tests.log` captured the focused passing upload API
  tests.
- `screenshots/invalid_upload_file_guard.png` summarizes the TDD proof.
- `video/invalid_upload_file_guard_proof.mp4` provides a 4.5 second proof
  video.

## Result

- Final disposition: passed for the missing-file guard. Broader corrupt-file
  and backend invalid-file cases remain out of this local slice.
