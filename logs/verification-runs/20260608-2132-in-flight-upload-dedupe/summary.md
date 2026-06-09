# Evidence Run: T-018: In-flight upload retry dedupe

- Source: docs/control/backlog-import.md
- Slug: `in-flight-upload-dedupe`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] UploaderService refuses to enqueue a retry for media that is already the current in-flight upload, preventing duplicate upload attempts for the same media path.

## Device Matrix

- UploaderService unit test runner, macOS host / Flutter test, role
  `upload-dedupe`, identifier `UploaderService in-flight duplicate guard`.

## Evidence

- `commands.log`: captured RED queue-length failure for an in-flight duplicate
  retry, then GREEN focused uploader service test run.
- `device-logs/uploader-dedupe-test-commands.log`: copy of the test command log
  for the evidence pack device-log requirement.
- `screenshots/in_flight_upload_dedupe.png`: rendered proof of the T-018
  duplicate retry guard.
- `video/in_flight_upload_dedupe_proof.mp4`: 4.5-second proof video for the
  same RED / CHANGE / GREEN flow.

## Result

- Final disposition: passed for the bounded T-018 local slice. Real upload smoke
  evidence remains the production closure gate for the broader mobile upload
  path.
