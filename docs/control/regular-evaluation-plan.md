# HydraCam Regular Evaluation Plan

Last reviewed: 2026-06-18 (content dated 2026-06-18).

Use this runbook whenever a change lands in the app. It turns the existing
evidence-first contract into a repeatable gate sequence for local development,
handoff, release prep, and device-facing work.

## Source Of Truth

- `AGENTS.md` defines repository operating rules and minimum validation.
- `docs/control/evidence-first-loop.md` defines evidence-pack requirements.
- `scripts/evidence_pack.py` creates, records, finalizes, and validates packs.
- `docs/control/status-and-roadmap.md` is the current platform/status reference.

Do not use emulator or simulator output as camera, gallery, local-network, or
release proof. Use emulators and simulators for launch, navigation, settings,
and non-camera app behavior. Use real hardware for camera, storage, upload,
network, profile/release launch, and master/slave claims.

## Gate Matrix

| Change type | Required checks | Required evidence |
| --- | --- | --- |
| Docs or instructions only | `git status -sb`; targeted `git diff --check -- <files>` | No evidence pack required unless device truth changed. |
| Any Dart or Flutter code | `flutter analyze --no-pub`; focused `flutter test --no-pub <targets>`; `git diff --check` | Add an evidence pack only when behavior is user/device-facing. |
| Shared services, app startup, session state, WebSocket, uploader, auth restore | Full `flutter test --no-pub` unless blocked; focused tests for the changed area | Tier D is enough for pure model/service logic; running-app changes need Tier A/B/C. |
| UI, navigation, settings, setup, standby, visual polish | Focused widget tests plus `scripts/run_hardware_ui_e2e.py` on emulator or Android hardware | Tier B/C pack with screenshots, video for multi-step flows, and device logs. |
| Camera, gallery, upload, storage, battery, network, release/profile launch | Focused tests plus physical-device verification | Tier A pack with real hardware model/OS, screenshots, video or capture artifacts, and logs. |
| Master/slave, discovery, sync, reconnect, role switching, multi-device capture | Focused tests plus rotating matrix or manifest/orchestrator run | Tier C or stronger pack with every intended target declared by id. |
| Store/TestFlight/Play readiness | `scripts/check_store_readiness.sh local` plus platform build/export checks for the lane being claimed | Release evidence pack or release artifact metadata; do not claim upload readiness without credentials. |

Before any handoff or commit, run the full `flutter test --no-pub` suite unless
the change is docs-only or the suite is explicitly blocked. If blocked, record
the skipped command and blocker in the evidence pack or final handoff.

## Start Every Run

Capture current repository and device truth first:

```bash
git status -sb
flutter devices --device-timeout 10
adb devices -l
xcrun devicectl list devices
```

For device-facing work, create the evidence pack before running the app:

```bash
python3 scripts/evidence_pack.py start \
  --item "<existing control-plane item>" \
  --slug "<short-run-slug>" \
  --source "docs/control/<source>.md#<section>" \
  --tier <A|B|C|D> \
  --acceptance "<observable acceptance check>" \
  --require-screenshots \
  --require-device-logs
```

Add each device or simulator before trusting artifacts:

```bash
python3 scripts/evidence_pack.py add-device logs/verification-runs/<run> \
  --name "<device name>" \
  --kind "<Android hardware|iOS hardware|Android emulator|iOS simulator>" \
  --identifier "<serial-or-udid>" \
  --role "<master|slave|single app instance|setup route|standby route>" \
  --os "<platform version>"
```

Record commands through the pack when practical:

```bash
python3 scripts/evidence_pack.py run logs/verification-runs/<run> -- \
  flutter analyze --no-pub
```

## Quick Lanes

### Static And Focused Tests

```bash
flutter analyze --no-pub
flutter test --no-pub <focused-test-file-or-directory>
git diff --check
```

Use focused tests that match the change. Examples: service changes use
`test/services/...`; master/slave changes use `test/master/...`,
`test/slave/...`, and relevant automation tests; UI changes use `test/widgets`
or `test/screens` files.

### Android Emulator UI Lane

```bash
python3 scripts/boot_and_verify_emulators.py --hydra-cluster --start --timeout 180
flutter test integration_test/platform_test.dart -d emulator-5554
flutter test integration_test/master_end_to_end_test.dart -d emulator-5554
python3 scripts/run_hardware_ui_e2e.py \
  --include-emulators \
  --device emulator-5554 \
  --route setup \
  --route standby \
  --run-dir logs/verification-runs/<run>
```

This lane proves launch, integration-test startup, automation routes,
screenshots, scroll checks, logs, and overflow detection. It does not prove real
camera capture.

### iOS Simulator UI Lane

```bash
flutter test integration_test/platform_test.dart -d <ios-simulator-udid>
xcrun simctl io <ios-simulator-udid> screenshot \
  logs/verification-runs/<run>/screenshots/ios-simulator.png
xcrun simctl spawn <ios-simulator-udid> log show --style compact --last 5m \
  > logs/verification-runs/<run>/device-logs/ios-simulator.log
```

Use this lane for launch, navigation, and initialization only. Do not use it for
camera or gallery proof.

### Single Android Hardware Lane

```bash
export HYDRACAM_WIFI_SSID="<venue ssid>"
# Provide HYDRACAM_WIFI_PASSWORD from your local shell or keychain; do not
# commit or log the passphrase.
python3 scripts/android_wifi_preflight.py \
  --expected-subnet auto \
  --device <adb-serial> \
  --check-only

python3 scripts/run_hardware_ui_e2e.py \
  --device <adb-serial> \
  --route setup \
  --route standby \
  --run-dir logs/verification-runs/<run>

python3 scripts/run_android_capture_profile.py \
  --serial <adb-serial> \
  --profile standard1080p30 \
  --lens autoBack \
  --output-dir logs/verification-runs/<run>
```

Use supported Android API 24+ hardware. Treat install-policy failures, locked
devices, wrong Wi-Fi, or missing `wlan0` as environmental blockers, not app
passes.

### Physical iOS Hardware Lane

```bash
python3 scripts/ios_capture_repro.py \
  --launch \
  --device-id <flutter-device-id> \
  --host auto \
  --scan-subnet 192.168.178.0/24 \
  --run-dir logs/verification-runs/<run> \
  --profile standard1080p30 \
  --lens autoBack
```

Before trusting the result, require an identity-matched automation bridge and an
iOS-native trace path under `/var/mobile/...`. If the bridge attaches to an
Android path under `/data/user/0/...`, rerun after isolating the iOS bridge.

## Multi-Device Lanes

Use the warm role-switch path for fast regression checks:

```bash
python3 scripts/run_rotating_master_slave_matrix.py \
  --prime-then-immediate-role-switch \
  --expect-target-id <device-id-1> \
  --expect-target-id <device-id-2> \
  --run-dir logs/verification-runs/<run>
```

Use pure immediate mode only after `/healthz` proves every selected bridge is
already warm:

```bash
python3 scripts/run_rotating_master_slave_matrix.py \
  --immediate-role-switch \
  --expect-target-id <device-id-1> \
  --expect-target-id <device-id-2> \
  --run-dir logs/verification-runs/<run>
```

Use `--fully-parallel-role-switch` only as a diagnostic comparison. Current
evidence favors the default staged-master plus parallel-slaves path.

For independent capture/lens/profile proof, use:

```bash
python3 scripts/run_parallel_device_matrix.py --run-dir logs/verification-runs/<run>
```

This proves per-device local capture under a shared command barrier. It is not
master/slave synchronization proof.

## Finish Every Evidence Run

Finalize the pack with the real outcome:

```bash
python3 scripts/evidence_pack.py finalize logs/verification-runs/<run> \
  --status <passed|failed|blocked|partial> \
  --note "<short factual result>"

python3 scripts/evidence_pack.py check logs/verification-runs/<run>
git status -sb
```

If a check cannot run because a device, SDK, signing identity, backend, or
credential is unavailable, record the skipped command and exact blocker. A
blocked evidence pack is acceptable; an unrecorded assumption is not.

## Defaults

- Re-inventory devices every run; never pin a stale live-device list in docs.
- Keep Android 6/API 23 out of active validation unless explicitly reopened.
- Keep `logs/verification-runs/latest-rotating-master-slave-warm-summary.json`
  as the hot role-switch cache; use `--expect-target-id` to prevent accidental
  target shrinkage.
- Use existing scripts before adding wrappers. Add a wrapper only after the same
  command chain is repeated often enough that manual command assembly becomes a
  real source of mistakes.
