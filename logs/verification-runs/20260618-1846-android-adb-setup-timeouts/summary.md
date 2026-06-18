# Evidence Run: Bound Android adb setup commands

- Source: docs/control/status-and-roadmap.md#android
- Slug: `android-adb-setup-timeouts`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] prepare_android_target reports adb install timeouts
- [x] prepare_android_target reports adb forward timeouts
- [x] bounded adb setup calls keep role-switch runner from hanging indefinitely

## Device Matrix

- Not applicable. Tier D runner-unit coverage for adb setup command handling.

## Evidence

- Red/green regression test:
  `python3 scripts/test_run_rotating_master_slave_matrix.py` first failed
  because `adb install` and `adb forward` timeouts escaped as raw
  `subprocess.TimeoutExpired` with no configured timeout, then passed after
  `prepare_android_target()` bounded both commands and raised per-device
  `MatrixRunError` messages.
- Verification passed:
  `python3 scripts/test_run_rotating_master_slave_matrix.py` and
  `git diff --check`.
- Full command output is recorded in `commands.log`.

## Result

- Final disposition: passed. Android setup cannot hang indefinitely on
  install/forward; the matrix now reports the failing target and command phase.
