# Evidence Run: Return client error for malformed automation bridge requests

- Source: docs/control/status-and-roadmap.md#latest-runtime-role-switch-matrix
- Slug: `automation-bridge-malformed-request`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Malformed command JSON returns HTTP 400 instead of bridge failure
- [x] Malformed command JSON does not invoke the registered automation handler

## Device Matrix

- Not applicable. Tier D HTTP-boundary unit coverage for the local automation
  bridge.

## Evidence

- Red/green regression test:
  `flutter test --no-pub test/automation/automation_bridge_test.dart` first
  failed because malformed command JSON returned `HTTP/1.1 500 Internal Server
  Error`, then passed after malformed request handling was split from generic
  bridge failures.
- Broader checks passed:
  `flutter test --no-pub test/automation`,
  `flutter analyze --no-pub`,
  `git diff --check`, and `flutter test --no-pub`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. The automation bridge command endpoint now returns
  `400 invalid_request` for malformed JSON request bodies and does not invoke
  the registered command handler.
