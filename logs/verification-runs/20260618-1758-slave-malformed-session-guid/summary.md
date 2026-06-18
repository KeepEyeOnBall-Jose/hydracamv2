# Evidence Run: Ignore malformed slave session identifiers

- Source: docs/control/backlog-import.md#2-preserve-session-state-across-master-reconnect
- Slug: `slave-malformed-session-guid`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Slave ignores sessionStatus/sessionStarted messages with non-string sessionGuid
- [x] Malformed session identifiers do not replace the active slave session or upload queue

## Device Matrix

- Not applicable. Tier D socket/unit coverage for slave WebSocket session
  message handling.

## Evidence

- Red/green regression test:
  `flutter test --no-pub test/slave/slave_client_registration_test.dart` first
  failed because malformed `sessionGuid` values produced cast errors and no
  explicit ignore logs, then passed after both `command` and `type`
  session-start/status paths used the shared guard.
- Broader checks passed:
  `flutter test --no-pub test/slave`,
  `flutter analyze --no-pub`,
  `git diff --check`, and `flutter test --no-pub`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. Malformed slave `sessionStatus` /
  `sessionStarted` identifiers are ignored without replacing the active slave
  session or upload queue.
