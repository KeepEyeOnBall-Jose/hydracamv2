# Evidence Run: Suppress stale identify acknowledgements after slave disconnect

- Source: docs/control/backlog-import.md#network-device-identity
- Slug: `slave-identify-ack-disconnect-race`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Disconnecting during identifyAck payload collection prevents stale identifyAck emission
- [x] The disconnect race does not log a JSON command processing error
- [x] Focused slave client test, analyzer, full Flutter suite, and diff hygiene pass

## Device Matrix

- Unit/integration-only verification on macOS host. No hardware was required for this Tier D identify/disconnect race regression.

## Evidence

- Red focused regression: `flutter test --no-pub test/slave/slave_client_registration_test.dart --plain-name "identifyAck is suppressed when disconnected during payload load"` failed before the implementation because the delayed identify payload path hit a null-channel command-processing error after disconnect.
- Green focused regression, full `test/slave/slave_client_registration_test.dart`, `flutter analyze --no-pub`, full `flutter test --no-pub`, and `git diff --check` passed. Command output is recorded in `commands.log`.

## Result

- Final disposition: passed.
