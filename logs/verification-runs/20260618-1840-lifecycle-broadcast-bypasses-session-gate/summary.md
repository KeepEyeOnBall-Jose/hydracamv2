# Evidence Run: Split session lifecycle broadcasts from capture command gating

- Source: docs/control/backlog-import.md#row-22-preserve-session-state-across-master-reconnect
- Slug: `lifecycle-broadcast-bypasses-session-gate`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Stale connected slaves receive sessionStarted for a new master session
- [x] Capture commands remain blocked for slaves reporting a different session
- [x] Focused master/slave socket regressions pass

## Device Matrix

- Not required for tier D integration/unit coverage.

## Evidence

- Red regression: `flutter test --no-pub test/master/master_network_snapshot_cache_test.dart --plain-name "session start broadcast reaches slaves with a different session"` failed because `sessionStarted` was skipped for a stale-session slave.
- Green regression: the same named test passed after splitting lifecycle broadcasts from capture-command session gating.
- Reviewer coverage: `flutter test --no-pub test/master/master_network_snapshot_cache_test.dart --plain-name "lifecycle broadcasts skip slaves on the wrong network"` passed.
- Reviewer coverage: `flutter test --no-pub test/master/master_network_snapshot_cache_test.dart --plain-name "ending master session broadcasts the ended session guid"` passed with both matching-session and stale-session slaves.
- Focused socket coverage: `flutter test --no-pub test/master/master_network_snapshot_cache_test.dart test/slave/slave_client_registration_test.dart` passed after a transient local WebSocket failure in the existing `startUploadingAll` slave test was rerun.
- Analyzer: `flutter analyze --no-pub` passed.
- Full suite: `flutter test --no-pub` passed.
- Diff hygiene: `git diff --check` passed.

## Result

- Final disposition: passed. Lifecycle broadcasts now bypass stale-session mismatch checks while preserving network eligibility; capture commands remain session-gated.
