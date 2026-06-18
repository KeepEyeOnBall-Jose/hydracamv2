# Evidence Run: Stabilize slave master-discovery listener lifecycle

- Source: docs/control/backlog-import.md#network-device-identity
- Slug: `master-discovery-idempotent-start`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Calling MasterDiscovery.startListening twice while active does not restart the socket
- [x] Stopping discovery resets listener state so it can start again
- [x] Focused discovery tests, analyzer, full Flutter suite, and diff hygiene pass

## Device Matrix

- Unit/integration-only verification on macOS host. No hardware was required for this Tier D lifecycle regression.

## Evidence

- Red focused regression: `flutter test --no-pub test/slave/master_discovery_test.dart --plain-name "startListening is idempotent while discovery socket is active"` failed before the implementation because the listener rebound twice.
- Green focused regression, full discovery test file, `flutter analyze --no-pub`, full `flutter test --no-pub`, and `git diff --check` passed. Command output is recorded in `commands.log`.

## Result

- Final disposition: passed.
