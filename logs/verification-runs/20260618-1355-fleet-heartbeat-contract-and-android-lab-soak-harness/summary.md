# Evidence Run: Fleet heartbeat contract and Android lab soak harness

- Source: docs/control/fleet-operations-plan.md
- Slug: `fleet-heartbeat-contract-and-android-lab-soak-harness`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Heartbeat payload emits documented stable health, warning, and blocker codes
- [x] Android always-on soak harness summarizes samples and writes durable evidence
- [x] Static analyzer and full Flutter tests pass for integrated checkout

## Device Matrix

- No attached Android devices were available. `adb devices -l` returned an empty
  device list, so this run does not claim a real 24-hour S10e soak.

## Evidence

- `commands.log` records:
  - `flutter test --no-pub test/services/fleet_heartbeat_service_test.dart`
  - `python3 scripts/test_run_android_always_on_lab_soak.py`
  - `python3 -m py_compile scripts/run_android_always_on_lab_soak.py scripts/test_run_android_always_on_lab_soak.py`
  - `flutter analyze --no-pub`
  - `flutter test --no-pub`
  - `git diff --check`
  - `adb devices -l`
- Review-driven hardening included:
  - Heartbeat collection now degrades to a warning/blocker payload when network
    or package-info plugin reads fail instead of dropping the heartbeat.
  - Optional soak `/healthz` probes now require an `automationTargetId` that
    matches one of the selected ADB device serials.

## Result

- Final disposition: passed for the app-side fleet heartbeat contract and
  Android lab soak harness. Real unattended-fleet proof still requires an
  attached powered S10e and a long-running soak pack.
