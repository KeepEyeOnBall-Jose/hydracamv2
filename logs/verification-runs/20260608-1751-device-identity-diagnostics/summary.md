# Evidence Run: Make network/device identity visible

- Source: docs/control/backlog-import.md#6-make-network-device-identity-visible
- Slug: `device-identity-diagnostics`
- Verification tier: B (emulator-simulator-e2e)
- Status: partial

## Acceptance Checks

- [x] Session diagnostics show network type and IP
- [x] Session diagnostics show a short local device ID
- [x] Session diagnostics show app version or a clear unavailable fallback
- [x] Session diagnostics show hardware identity or a clear unavailable fallback
- [x] Long diagnostics fit narrow panes without layout exceptions

## Device Matrix

- `flutter-test`: macOS Flutter widget test runner, simulated app surface for
  `SessionInfoWidget` diagnostics proof.

## Evidence

- Screenshot: `screenshots/session_identity_diagnostics.png`
- Video: `video/session_identity_diagnostics_proof.mp4`
- Device/test log: `device-logs/flutter-widget-runner.log`
- Commands: `commands.log`
- RED proof 1: focused widget tests first failed because the device/app
  diagnostics line did not exist.
- RED proof 2: focused widget tests then failed because the hardware line did
  not exist.
- GREEN proof: focused widget tests pass after implementation.
- Analyzer: `flutter analyze --no-pub` passes.

## Result

- Final disposition: partially completed. The existing session diagnostics
  widget now shows network/IP, short device ID, app version fallback, and
  hardware fallback with narrow-pane coverage. Keep the existing board item open
  for disconnected-device state and broader master device-list UX refinements.
