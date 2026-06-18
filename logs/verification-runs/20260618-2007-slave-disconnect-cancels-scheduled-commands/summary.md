# Evidence Run: Cancel pending scheduled slave commands on disconnect

- Source: docs/control/backlog-import.md#support-synchronized-time-accurately-enough-for-capture
- Slug: `slave-disconnect-cancels-scheduled-commands`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] SlaveClient.disconnect cancels pending scheduled capture commands
- [x] Scheduled-command countdown behavior still applies master clock offset while connected
- [x] Focused slave client test, analyzer, full Flutter suite, and diff hygiene pass

## Device Matrix

- Unit/integration-only verification on macOS host. No hardware was required for this Tier D scheduled-command lifecycle regression.

## Evidence

- Red focused regression: `flutter test --no-pub test/slave/slave_client_registration_test.dart --plain-name "disconnect cancels pending scheduled slave commands"` failed before the implementation because the scheduled task remained registered after `SlaveClient.disconnect()`.
- Green focused regression, scheduled-command focused tests, full `test/slave/slave_client_registration_test.dart`, `flutter analyze --no-pub`, full `flutter test --no-pub`, and `git diff --check` passed. Command output is recorded in `commands.log`.

## Result

- Final disposition: passed.
