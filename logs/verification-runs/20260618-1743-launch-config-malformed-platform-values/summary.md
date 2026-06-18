# Evidence Run: Ignore malformed platform launch config values

- Source: docs/control/backlog-import.md#1-validate-ios-releaseprofile-launch-and-capture-readiness
- Slug: `launch-config-malformed-platform-values`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Malformed non-string platform launch config values do not throw during load
- [x] Valid boolean manual launch values remain honored

## Device Matrix

- Not applicable. Tier D parser/unit coverage for launch-config automation
  startup path.

## Evidence

- Red/green regression test:
  `flutter test --no-pub test/automation/runtime_role_switch_test.dart`
  failed before the parser guard with
  `type 'int' is not a subtype of type 'String?' in type cast`, then passed
  after the change.
- Broader checks passed:
  `flutter test --no-pub test/automation`,
  `flutter analyze --no-pub`,
  `git diff --check`, and `flutter test --no-pub`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. `LaunchConfigService` now ignores malformed
  non-string platform launch-config values instead of crashing startup while
  still honoring valid boolean `manualLaunch` values.
