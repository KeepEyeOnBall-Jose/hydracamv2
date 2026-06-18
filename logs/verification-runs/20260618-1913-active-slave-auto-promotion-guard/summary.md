# Evidence Run: Prevent active slave auto-promotion on master-loss timeout

- Source: docs/control/device-relationship-fsm.md#minimal-implementation-slices
- Slug: `active-slave-auto-promotion-guard`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Auto-mode slave with no active session can still promote after discovery timeout
- [x] Auto-mode slave with an active session remains in slave recovery instead of promoting itself
- [x] Focused slave-screen tests, analyzer, full Flutter suite, and diff hygiene pass

## Device Matrix

- Static Flutter widget test lane on local macOS host; no attached device
  required for this deterministic master-loss promotion guard.

## Evidence

- Red coverage showed the active-session recovery status was missing before the
  guard.
- A deterministic fake `MasterDiscovery` drives the auto-mode timeout path
  without binding a real UDP listener.
- Focused widget coverage proves an active slave session remains on
  `SlaveScreen` with `Master unavailable; preserving active session ...`.
- Focused widget coverage also proves idle auto-mode startup still follows the
  existing promotion path.
- `flutter test --no-pub test/slave/slave_screen_fast_connect_test.dart`
  passed.
- `flutter analyze --no-pub` passed.
- `flutter test --no-pub` passed with 474 tests.
- `git diff --check` passed.

## Result

- Final disposition: passed. Auto-mode slaves no longer self-promote while an
  active slave session exists, reducing split-brain risk until the broader
  authority/election contract is implemented.
