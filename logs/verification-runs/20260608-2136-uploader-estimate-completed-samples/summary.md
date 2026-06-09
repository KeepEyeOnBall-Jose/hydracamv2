# Evidence Run: T-020: Upload estimate uses completed samples

- Source: docs/control/backlog-import.md
- Slug: `uploader-estimate-completed-samples`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] UploaderService estimates queued upload time from completed upload samples, so a later queued media item gets a non-zero estimate based on observed bytes per second.

## Device Matrix

- UploaderService unit test runner, macOS host / Flutter test, role
  `upload-estimate`, identifier `UploaderService completed-sample estimate`.

## Evidence

- `commands.log`: captured RED failure for missing deterministic service clock
  support, then GREEN focused uploader service test run with a 10-second
  estimate from completed sample throughput.
- `device-logs/uploader-estimate-test-commands.log`: copy of the test command
  log for the evidence pack device-log requirement.
- `screenshots/uploader_estimate_completed_samples.png`: rendered proof of the
  T-020 completed-sample estimate path.
- `video/uploader_estimate_completed_samples_proof.mp4`: 4.5-second proof video
  for the same RED / CHANGE / GREEN flow.

## Result

- Final disposition: passed for the bounded T-020 local slice. Real upload smoke
  evidence remains the production closure gate for the broader mobile upload
  path.
