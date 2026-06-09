# Evidence Run: Backlog row 40: Storage location missing-state

- Source: docs/control/backlog-import.md
- Slug: `storage-location-missing-state`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Settings makes the current app storage location explicit and states that SD-card selection is not configured.

## Device Matrix

- Settings widget test runner; macOS host / Flutter test; identifier:
  `SettingsScreen storage location state`; role: storage-settings.

## Evidence

- `device-logs/red-tests.log` captured the missing settings labels.
- `device-logs/green-focused-tests.log` captured the focused passing
  SettingsScreen widget tests.
- `screenshots/storage_location_missing_state.png` summarizes the TDD proof.
- `video/storage_location_missing_state_proof.mp4` provides a 4.5 second proof
  video.

## Result

- Final disposition: passed for the visible settings missing-state. This does
  not claim SD-card selection or alternate storage writes are implemented.
