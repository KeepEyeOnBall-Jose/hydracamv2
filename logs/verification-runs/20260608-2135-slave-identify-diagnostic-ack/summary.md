# Evidence Run: Backlog row 47: Master asks slaves whether alive via diagnostic ack

- Source: docs/control/backlog-import.md
- Slug: `slave-identify-diagnostic-ack`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Master can send an identity-safe diagnostic command to a selected slave and store the slave acknowledgement in connected-device diagnostics.

## Device Matrix

- Loopback master/slave WebSocket; macOS host / Flutter test; identifier:
  `targeted identifySlave ack`; role: master-slave-diagnostics.

## Evidence

- `device-logs/red-tests.log` captured the missing master identify API and
  slave unknown-command timeout.
- `device-logs/green-focused-tests.log` captured the focused passing
  master/slave/payload regression tests.
- `screenshots/slave_identify_diagnostic_ack.png` summarizes the TDD proof.
- `video/slave_identify_diagnostic_ack_proof.mp4` provides a 4.5 second proof
  video.

## Result

- Final disposition: passed for the local diagnostic acknowledgement slice.
  This does not claim real flash/frame hardware identification proof.
