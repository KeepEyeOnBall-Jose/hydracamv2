# Evidence Run: Backlog row 36: Null check error stopping recording on macOS/iPad

- Source: docs/control/backlog-import.md
- Slug: `forced-stop-missing-start-timestamp`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Forced recording stop records media even when the camera start timestamp is missing, using a safe fallback instead of a null-check failure.

## Device Matrix

- Flutter service test runner; macOS host / Flutter test; identifier:
  `CameraService mock forced stop`; role: forced-stop-recording.

## Evidence

- `device-logs/red-tests.log` captured the pre-fix null-check failure.
- `device-logs/green-focused-tests.log` captured the focused passing
  regression test.
- `screenshots/forced_stop_missing_start_timestamp.png` summarizes the TDD
  proof.
- `video/forced_stop_missing_start_timestamp_proof.mp4` provides a 4.5 second
  proof video.

## Result

- Final disposition: passed for the local forced-stop timestamp regression.
  This does not claim fresh real macOS/iPad reproduction proof.
