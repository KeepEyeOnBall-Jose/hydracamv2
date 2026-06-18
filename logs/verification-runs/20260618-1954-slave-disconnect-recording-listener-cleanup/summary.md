# Evidence Run: Unregister slave recording-interrupt listeners on disconnect

- Source: docs/control/backlog-import.md#preserve-session-state-across-master-reconnect
- Slug: `slave-disconnect-recording-listener-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] SlaveClient.disconnect removes its CameraService recordingInterrupted listener
- [x] Focused slave client lifecycle test, analyzer, full Flutter suite, and diff hygiene pass

## Device Matrix

- Unit/integration-only verification on macOS host. No hardware was required for this Tier D lifecycle regression.

## Evidence

- Red focused regression: `flutter test --no-pub test/slave/slave_client_registration_test.dart --plain-name "disconnect removes recording interruption listener"` failed before the fix because the disconnected client still received the recording-interruption callback.
- Green focused regression, full `test/slave/slave_client_registration_test.dart`, `flutter analyze --no-pub`, full `flutter test --no-pub`, and `git diff --check` passed. Command output is recorded in `commands.log`.

## Result

- Final disposition: passed.
