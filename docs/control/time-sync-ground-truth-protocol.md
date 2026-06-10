# Clock-Sync Ground-Truth Verification Protocol

Operator protocol for empirically validating HydraCam's cross-device
clock-synchronization feature against the **< 50 ms** cross-device alignment
target from the NTP sync specification.

This protocol measures the *real* alignment error between two devices by
filming a single sharp synchronized visual event in both camera views and
checking whether the per-clip sync metadata places that one real-world event at
the same instant on the shared (master) clock.

## Requirements (read first)

- **Real hardware with working cameras is mandatory.** This cannot be run on a
  simulator or emulator: it depends on two physical cameras capturing the same
  physical light event at the same time. Simulators have no real shutter/sensor
  timing and cannot observe a shared flash.
- Two devices: one **master**, one **slave** (any supported iOS/Android device
  per `docs/control/status-and-roadmap.md`).
- Both devices on the **same hotspot / LAN** (the master's WebSocket server runs
  on port 4040; the slave must be able to reach it).
- A sharp, instantaneous shared visual event source that both cameras can see at
  once, for example:
  - a **camera flash** / strobe fired once in frame, or
  - a **clap board** (slate) snapping shut, or
  - a single bright LED toggled on for one frame.
  Prefer something with a crisp single-frame transition so you can read the
  event frame unambiguously in each clip.

## Procedure

1. **Pair the devices.**
   - Start the master; create or join a backend session.
   - Start the slave on the same hotspot; let it discover and connect to the
     master.

2. **Wait for green sync.** On the slave, wait until the on-screen sync status
   chip reads **green**. Do not proceed on yellow/red unless you are
   intentionally capturing a degraded-sync negative case. Record the chip
   confidence for both devices at the moment of capture.

3. **Start recording on both devices** (via the master's record command so both
   start near-simultaneously). Keep both cameras pointed so the shared event
   will be visible in both frames.

4. **Produce the synchronized event in BOTH camera views.** Fire the flash /
   snap the clap board **once** (or a few times, spaced a couple seconds apart,
   so you have redundant events to cross-check). Make sure the event is clearly
   visible in both clips.

5. **Stop recording on both devices.** Let each clip finish and its
   `<mediaPath>.sync.json` sidecar be written (this is written by
   `lib/services/session_manager.dart` on `addVideo` / `addPhoto`).

6. **Locate the event frame in each clip** and note its **media-relative
   timestamp in seconds** (time from the start of that clip to the event frame).
   Do this independently for each clip — the two values will differ because the
   two devices did not start recording at exactly the same instant. If you fired
   multiple events, record an offset pair per event.
   - For **photos** (no recording window), the event offset is `0` — the
     `captureDate` already is the event instant.

7. **Collect the two sidecars.** Find each clip's `<mediaPath>.sync.json`
   (next to the media file in the session directory; can be pulled off-device).

8. **Run the analysis script** (standard library Python 3, no third-party deps):

   ```bash
   python3 scripts/analyze_sync_alignment.py \
     --clip-a <path/to/deviceA.mp4.sync.json> --event-a <secondsA> \
     --clip-b <path/to/deviceB.mp4.sync.json> --event-b <secondsB>
   ```

   The script:
   - parses each sidecar's recording-start date (`startRecordingDate`, or
     `captureDate` for photos) and the `sync` block (`offsetMs`,
     `uncertaintyMs`, `confidence`);
   - computes each clip's event time on the shared clock as
     `startDate + eventSeconds + offsetMs`;
   - reports the two shared-clock event times, the signed alignment error in ms,
     the combined uncertainty, both confidence tiers, and a PASS/FAIL verdict.

## How the numbers are computed

The sync model (see `lib/services/session_manager.dart` and
`lib/models/sync_metadata.dart`):

- A device's local clock relates to the shared master clock by
  `sharedClockTime = localTime + offsetMs`, where `offsetMs = master - local`.
- `startRecordingDate` is already the device's wall-clock UTC start of the clip.
- The event's device wall-clock time is `startRecordingDate + eventSeconds`.
- The event's **shared-clock** time is `startRecordingDate + eventSeconds + offsetMs`.
- The **cross-device alignment error** is the difference of the two clips'
  shared-clock event times. For one real-world event observed by both cameras,
  a perfect sync gives an error of 0 ms.

**Combined uncertainty** uses root-sum-square (RSS):
`combined = sqrt(uA^2 + uB^2)`. RSS (not the linear sum `uA + uB`) is used
because the two devices' calibration uncertainties are independent error
estimates, and RSS is the standard propagation for independent uncertainties.

## Pass criterion

A run **PASSES** when:

```
|alignment error| + combined uncertainty < 50 ms
```

Always also record the **green / yellow / red** confidence of *both* clips. A
numeric pass on non-green clips should be treated with caution — the script
emits a note in that case. Prefer re-capturing until both clips are green.

## Recording results

Copy `logs/verification-runs/time-sync-ground-truth-template/` to a new dated
run directory under `logs/verification-runs/` and fill in the README there:
device models/OS, roles, hotspot, chip confidence at capture, both
`.sync.json` contents, the observed event offsets, the exact script command and
its full output, and the final PASS/FAIL. Per
`docs/control/evidence-first-loop.md`, this device-facing capture work needs a
run-specific evidence pack with the real artifacts.
