# Evidence Run: Bound Android ADB setup and launch calls in rotating matrix

- Source: AGENTS.md#multi-device-synchronization-evidence
- Slug: `rotating-matrix-adb-timeout-guards`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Python tests prove Android permission-grant and force-stop timeouts do
  not hang the runner, launch timeouts surface as `MatrixRunError`, and the
  runner still compiles.

## Device Matrix

- macOS host, macOS 26.4.1, `macos`, local tooling test host.
- No Android hardware matrix was run; this pack validates timeout handling in
  runner unit tests.

## Evidence

- `commands.log` records:
  - `python3 scripts/test_run_rotating_master_slave_matrix.py`
  - `python3 -m py_compile scripts/run_rotating_master_slave_matrix.py scripts/test_run_rotating_master_slave_matrix.py`

## Result

- Final disposition: passed for static/tooling validation. A real selected-set
  matrix still needs attached devices on one reachable LAN before claiming a
  new hardware benchmark.
