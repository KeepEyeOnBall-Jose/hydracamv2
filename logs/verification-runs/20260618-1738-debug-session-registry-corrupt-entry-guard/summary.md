# Evidence Run: Skip corrupt debug session registry entries

- Source: docs/control/backlog-import.md#2-preserve-captured-materials-through-reconnect
- Slug: `debug-session-registry-corrupt-entry-guard`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Debug session registry list skips malformed persisted JSON entries
- [x] Debug session registry list still returns valid persisted entries

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Recorded a red focused registry test showing malformed persisted JSON broke
  `DebugSessionRegistry.list()`, then reran the focused registry test,
  registry cleanup test, `flutter analyze --no-pub`, `git diff --check`, and
  full `flutter test --no-pub`.

## Result

- Final disposition: passed
