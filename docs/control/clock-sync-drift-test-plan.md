# Clock-Sync Drift Test Plan

> Last reviewed: 2026-06-24 (content dated 2026-06-24)
> Created: 2026-06-24

Hardware ground-truth test for multi-camera time synchronization. Every camera
films the same machine-readable millisecond clock; we read the clock value out
of the captured frames and measure how far apart the cameras place the same
real-world instant on their shared clock.

## Why

The existing sync stack already has:

- An NTP-style `SyncMetadata` model (`offsetMs`, `uncertaintyMs`, `confidence`)
  and `sharedClockTime = localTime + offsetMs` — see `lib/models/sync_metadata.dart`
  and `lib/services/time_sync_service.dart`.
- A per-recording `.sync.json` sidecar.
- A ground-truth analyzer `scripts/analyze_sync_alignment.py` that, given two
  sidecars plus the media-relative time of one synchronized visual event in each
  clip, reports cross-device alignment error against a `< 50 ms` target.

Today the "event" is a manual clap/flash that a human locates in each clip. This
test **automates and scales that**: a filmed clock provides a continuously
machine-readable event, so the per-clip event time is read by software, for N
cameras at once, and against absolute wall-clock ground truth.

## Components

- **Clock target** — `scripts/clock-sync/clock.html`. Fullscreen page showing a
  47-cell binary strip: a RED start fiducial, 44 white/black data cells encoding
  `Date.now()` epoch ms (44-bit, big-endian, MSB by the red cell), an even-parity
  cell, and a GREEN end fiducial, plus human-readable UTC digits. Keep the
  display machine NTP-synced. Show it on a screen all cameras point down at.
- **Frame reader / drift analyzer** — `scripts/clock-sync/clock_drift_from_frames.py`.
  Extracts frames (ffmpeg), decodes the strip per frame (locate red/green
  fiducials, sample cells, verify parity), and computes:
  - per-camera sync error vs ground truth:
    `error = (startRecordingDate + media_seconds + offsetMs) − decoded_clock`;
  - pairwise cross-camera drift `mean_error_A − mean_error_B` with RSS-combined
    uncertainty and PASS/FAIL against the 50 ms target (imports
    `analyze_sync_alignment` for the shared math);
  - interpolated event-seconds at a common clock instant, for cross-checking
    against `analyze_sync_alignment.py` directly.
  Validated offline by `--self-test` (renders synthetic strips, round-trips the
  decoder, checks the drift math) — no camera needed. Requires `cv2`/`numpy`
  (use the cv-compute venv).

## The loop

1. **Deploy** the fleet: `scripts/hybrid_deploy.sh deploy` (see the hybrid
   deploy plan). Wait for green sync confidence on the slaves.
2. **Aim** every camera (this is the only manual step): point all cameras down
   at one screen showing `clock.html` fullscreen, clock filling the frame.
3. **Capture**: `scripts/clock-sync/run_clock_sync_capture.sh run 15` — drives
   the master automation bridge (`start_session` → `start_recording` → wait →
   `stop_recording` → `end_session`), then pulls each device's session videos +
   `.sync.json` sidecars (via `run-as` on the debug build), then runs the
   analyzer.
4. **Read the report**: per-camera absolute sync error and pairwise drift, with
   PASS/FAIL at 50 ms, plus a `drift-summary.json`.

## What "good" looks like

- Each camera's per-clip error is near-constant (low stdev) — internally
  consistent timing.
- The absolute error value reveals true offset from wall-clock (the clock is
  ground truth; the app's NTP sync is master-relative, so a shared constant
  across cameras is fine; what matters is **agreement between cameras**).
- Every camera pair's `|drift| + combined_uncertainty < 50 ms`.

## Capture-quality notes

- Use a high frame-rate profile (`sport1080p60`) so the fast clock is sampled
  finely; default extraction is ~10 fps but raise `--fps` for tighter
  interpolation.
- Phone refresh vs camera exposure can occasionally catch a torn value; the
  parity cell makes the reader reject those frames automatically.
- Keep the strip large and roughly fronto-parallel (cameras pointing straight
  down at a flat screen) so fiducial detection and cell sampling stay robust.

## Status (2026-06-24)

- Clock target, analyzer (self-test green), deploy tool, and capture
  orchestrator are built and committed.
- The build → deploy → record → pull → extract loop is validated on the local
  S10e (see `logs/verification-runs/`). The full multi-camera drift number is
  pending one physical shoot (clock under the downward cameras).
