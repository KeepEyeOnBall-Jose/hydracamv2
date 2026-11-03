# Two-Device Clock-Sync Capture Runbook (Operator)

Last reviewed: 2026-06-10 (content dated 2026-06-10).

Step-by-step procedure for performing the **real** two-device capture that
exercises HydraCam's clock-synchronization feature end to end on physical
hardware, confirms the slave's sync status chip is green, captures a photo and a
video, and pulls the `metadata.json` + `<media>.sync.json` artifacts off each
device.

This runbook covers the *capture and artifact-collection* mechanics. For the
**alignment measurement** (the clap/flash ground-truth that proves the
cross-device error is within the < 50 ms target), follow
`docs/control/time-sync-ground-truth-protocol.md` after you have a green capture.

> Status: **NOT YET EXECUTED.** This is the operator template. The software-level
> evidence that the calibration-to-persistence path works is already captured at
> `logs/verification-runs/20260610-time-sync-software-evidence/`. The physical
> two-device run below is pending operator action.

## Device targets

| Role   | Candidate devices                                  | Availability (2026-06-10)                                                                                                                                                                                                                                                                                         |
|--------|----------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Master | Any supported device (see `status-and-roadmap.md`) | Android Samsung S7 / S9 / S10e have recent passing launch evidence; use one as master.                                                                                                                                                                                                                            |
| Slave  | Any supported device                               | A second Android device (S9/S10e) is the most reliable slave right now.                                                                                                                                                                                                                                           |
| iOS    | iPhone / iPad                                      | **OFFLINE** — recent runs recorded iOS device visibility/warm-prime failures (`logs/verification-runs/20260609-0557-ios-iphone-ipad-not-working`, `…-recovery-continuation`, and the iOS warm-prime failure evidence). Do not assume iOS is available; confirm device visibility before selecting an iPhone/iPad. |

Pick two devices that are currently reachable (Android recommended today). Record
the exact device models you used in the results section.

## Preconditions

- Both devices on the **same hotspot / LAN**. The master's WebSocket server
  listens on **port 4040**; the slave must be able to reach
  `ws://<master-ip>:4040/ws`.
- Both apps installed from the same build; cameras grant-able.
- Enough free storage on both devices for a photo and a short video.

## Procedure

1. **Start the master.**
   - Launch HydraCam, choose the master role.
   - Create or join a **backend** session (local-only sessions are not
     uploadable and will not produce the same metadata).
   - Confirm the master log shows `WebSocket Server successfully started`.

2. **Start the slave and pair.**
   - Launch HydraCam on the second device on the same hotspot, choose the slave
     role, and let it discover/connect to the master.
   - Confirm the master shows the slave as **Connected**.

3. **Wait for green sync on the slave.**
   - On the slave screen, watch the **clock-sync status chip**.
   - It begins as grey **"Clock sync: calibrating…"**, then updates to a colored
     dot with text like **"Clock sync: ±NN ms · RTT NN ms · 8 samples"**.
   - Wait until the dot is **green**. Green requires uncertainty ≤ 25 ms and a
     fresh calibration (< 60 s old). The slave re-calibrates every 30 s.
   - Record the chip text (uncertainty, RTT, sample count, color) for the slave.
     The master is the reference clock (offset 0 by definition).

4. **Capture a photo.**
   - From the master, trigger a `takePhoto` (or scheduled capture) to the slave.
   - Confirm the slave reports "Photo taken and saved locally."

5. **Capture a video.**
   - From the master, start recording, wait a few seconds, then stop.
   - Confirm the slave reports the recording stopped and saved.

6. **(Optional but recommended) Capture the ground-truth event.**
   - While both cameras are rolling, fire the shared flash / snap the clap board
     once in both frames so the alignment can be measured later per
     `docs/control/time-sync-ground-truth-protocol.md`.

7. **Pull the artifacts off each device.**
   - Each session is stored under the app documents directory as
     `session_<sessionGuid>/`.
   - For each device, collect:
     - `session_<sessionGuid>/metadata.json` — contains a `photos[]` and
       `videos[]` array; each entry has a `syncMetadata` block with
       `offsetMs`, `minRoundTripMs`, `uncertaintyMs`, `confidence`,
       `sampleCount`, `calibratedAt`, `calibrationAgeMs`.
     - The `<media>.sync.json` sidecar sitting next to each captured `.jpg` /
       `.mp4` — contains the same fields under a `sync` block, plus the media
       path, device id, capture timestamps and session GUID.
   - Transfer methods (pick what works for the platform):
     - Android: `adb pull /data/data/<package>/app_flutter/session_<guid> ./pull/`
       (path may differ by build; or use the in-app export / Files access).
     - iOS: Finder / Xcode device container access, or the in-app export.

8. **Sanity-check the pulled artifacts.**
   - Open the slave's `metadata.json`; confirm each captured photo/video entry
     has a `syncMetadata` block whose `confidence` matches the chip you saw.
   - Open one `<media>.sync.json` sidecar; confirm its `sync.offsetMs` matches
     the corresponding entry in `metadata.json`.
   - The master's media entries are the reference (offset 0).

## Where to record results

Create a sibling evidence run folder and drop the pulled artifacts and notes
there:

```text
logs/verification-runs/<YYYYMMDD>-time-sync-two-device-hardware/
  README.md            # device models, hotspot, chip color/text per device, pass/fail
  master-metadata.json
  slave-metadata.json
  master-<media>.sync.json
  slave-<media>.sync.json
  photos/ videos/      # optional: the captured clips for the alignment step
```

In that `README.md` record, at minimum:

- Master and slave device models and OS versions.
- The slave sync-chip color and exact text at capture time.
- Whether a green capture was achieved.
- For the alignment measurement, the measured cross-device error and whether it
  met the **< 50 ms** target (see the ground-truth protocol).

## Related

- Ground-truth alignment measurement:
  `docs/control/time-sync-ground-truth-protocol.md`
- Software-level evidence (calibration + persistence path, already executed):
  `logs/verification-runs/20260610-time-sync-software-evidence/`
