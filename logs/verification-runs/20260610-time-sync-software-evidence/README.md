# Clock-Sync Software-Level Evidence — 2026-06-10

Reproducible **software-level** evidence that HydraCam's clock-sync feature works
end to end, from NTP-style calibration through to the per-capture sync metadata
that is persisted in `metadata.json` and in the `<media>.sync.json` sidecar.

> **Scope / honesty note.** This is software-level evidence produced by automated
> tests run in this environment. It does **not** include real two-device camera
> capture: physical iOS devices were offline, there was no Android device
> attached, and simulators have no camera. The physical two-device capture and
> the clap/flash alignment measurement are **pending operator action** and are
> delivered as the runbook at
> [`docs/control/time-sync-two-device-runbook.md`](../../../docs/control/time-sync-two-device-runbook.md)
> (alignment measurement: `docs/control/time-sync-ground-truth-protocol.md`).
> No device logs or screenshots in this pack are fabricated; every artifact here
> is the real output of the tests below.

## What was tested

1. **End-to-end calibration + persistence** —
   `test/integration/two_device_sync_capture_test.dart`
   - Starts a **real `MasterServer`** bound to a loopback ephemeral port (only
     the network snapshot and media-storage root are injected; the sync handling
     is the production code path).
   - Connects a **real `SlaveClient`** over `ws://127.0.0.1:<port>/ws`.
   - The slave fires its real `timeSyncRequest` burst, the master answers with
     `_handleTimeSyncRequest`, and `TimeSyncService` calibrates. The test asserts
     `sampleCount > 0` and a sane loopback offset (< 2 s), and that the offset is
     applied to the scheduling clock.
   - Sends a **real `takePhoto` command** from the master to the registered
     slave. The slave captures via the mock camera (which writes a real temp
     file), constructs a `CapturedPhoto` with `syncMetadata`, and `SessionManager`
     persists `metadata.json` + the `<media>.sync.json` sidecar.
   - Asserts the persisted photo entry and the sidecar both carry a sync block
     with `offsetMs`, `uncertaintyMs`, `confidence`, `sampleCount`,
     `calibrationAgeMs`, and that the two agree on `offsetMs`.

2. **Slave sync-status chip rendering** —
   `test/slave/slave_screen_sync_chip_test.dart`
   - Mirrors `SlaveScreen._buildSyncStatusChip` against the public
     `TimeSyncService` singleton.
   - Asserts the **"calibrating…"** placeholder when no calibration exists, and
     the **offset / RTT / sample** summary plus the **green** confidence dot once
     a green `TimeSyncResult` is recorded.

## Exact commands

```bash
# Whole-project static analysis (clean).
flutter analyze

# The two sync tests, exporting the real artifacts captured in this folder.
SYNC_EVIDENCE_DIR="logs/verification-runs/20260610-time-sync-software-evidence" \
  flutter test test/integration/two_device_sync_capture_test.dart \
               test/slave/slave_screen_sync_chip_test.dart \
               --reporter expanded

# Full suite (regression check).
flutter test
```

## Results (real)

- `flutter analyze` → **No issues found!**
- Sync tests (`two_device_sync_capture_test.dart` +
  `slave_screen_sync_chip_test.dart`) → **+3: All tests passed!**
  (see [`test-output.log`](./test-output.log)).
- Full suite (`flutter test`) → **All tests passed!**
  (309 passed, 1 skipped, 0 failed).
- Observed real calibration in the integration run:
  `Clock synced to master: offset 1 ms, uncertainty 13 ms, RTT 25 ms, 8 samples,
  green.`

## Artifacts in this folder

- [`test-output.log`](./test-output.log) — real captured stdout of the sync-test
  run (`--reporter expanded`, log noise filtered).
- [`sample-metadata.json`](./sample-metadata.json) — the real `metadata.json`
  written by the integration test, including the `photos[].syncMetadata` block.
- [`sample-media.sync.json`](./sample-media.sync.json) — the real
  `<media>.sync.json` sidecar written next to the captured photo, including the
  `sync` block.

Both sample artifacts were emitted by the integration test itself (via the
`SYNC_EVIDENCE_DIR` export hook) and are byte-for-byte the data the production
`SessionManager` persisted during the run.

## Pending (operator)

Physical two-device capture + alignment measurement on real hardware:
- Runbook: `docs/control/time-sync-two-device-runbook.md`
- Alignment protocol: `docs/control/time-sync-ground-truth-protocol.md`
- Device note: iOS targets were offline on 2026-06-10; Android (S7/S9/S10e) had
  recent passing launch evidence and is the recommended hardware path.
