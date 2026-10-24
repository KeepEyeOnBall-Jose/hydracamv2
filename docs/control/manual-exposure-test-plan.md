# Manual exposure test plan

Goal: measurable squash ball streaks at 4K 30 fps. A streak is only measurable
when the shutter time is known and fixed for the whole clip, so each clip
records the values the sensor actually used (`captureContext.exposure`).

## What the app does

- Setting **Exposure preset** (Settings, or automation `exposurePreset`):
  `auto`, `shutter1_30`, `shutter1_60` (default), `shutter1_120`.
- For a manual preset, recording start locks shutter, ISO, white balance and
  focus. ISO is metered once from auto exposure (shutter priority) and held.
  The lock is released when recording stops.
- Android: Camera2 interop on the camera CameraX bound (incl. 0.5x ultra-wide).
  Needs the `MANUAL_SENSOR` capability, else `lockStatus: unsupported`.
- iOS: AVFoundation custom exposure, locked white balance and focus.
- If the lock fails, recording still runs; `lockStatus` says why.

## Per-clip metadata

Stored in the clip's capture context and sent with the upload as
`captureSettings` (multipart field, or bridge `metadata.captureSettings`):

| Field | Meaning |
| --- | --- |
| `preset` | selected preset |
| `lockStatus` | `locked`, `auto`, `unsupported`, `no_camera`, `unavailable`, `error` |
| `requestedExposureTimeNs` | preset shutter |
| `exposureTimeNs` | shutter the sensor used (capture result / device) |
| `iso` | ISO used |
| `frameDurationNs`, `fps` | frame timing used |
| `rollingShutterSkewNs` | Android only; iOS does not expose readout time |
| `underexposed` | metered ISO wanted more than the sensor max |
| `lock`, `start`, `stop` | raw native snapshots |

## Expected streak length

streak = ball speed × shutter. At 30 m/s: 1/30 → 1.0 m, 1/60 → 0.5 m,
1/120 → 0.25 m. Use court markings (tin height 0.48 m, service line 1.78 m)
as scale.

## Rally drill

Same drill for every cell: one player, 20 straight drives along the side
wall from the short line, ball warmed up, court lights at match level. Phone on
the tin mount (`tin_back_floor_center`), 0.5x ultra-wide, profile
`detail4k30`, session started locally, auto upload off.

| Phone | auto | 1/30 | 1/60 | 1/120 |
| --- | --- | --- | --- | --- |
| Galaxy S10e (SM-G970F) | | | | |
| Galaxy S20 FE (SM-G780G / G781B) | | | | |
| iPhone | | | | |

For each cell record:

1. `lockStatus` is `locked` (or `auto` for auto).
2. `exposureTimeNs` within 5% of `requestedExposureTimeNs`.
3. `iso` and `underexposed`. If `underexposed`, note the court lux.
4. 5 drives: streak length in px and m, both ends visible (yes/no).
5. Noise and flicker: visible banding under court LEDs (yes/no).

Pass: on each phone at least one manual preset gives clean streaks with
both ends visible in 4 of 5 drives, and `exposureTimeNs` is stable across the
start and stop snapshots.

## Automation smoke (no court needed)

```bash
python3 scripts/run_android_capture_profile.py --serial <serial> \
  --lens ultraWide --profile detail4k30 \
  --manifest automation_scenarios/single_device_exposure_presets.json
```

The manifest starts a debug service session (`start_session`), so the phone
needs internet; without it the run times out at the first await.

Then check `adb logcat | grep "Recorded exposure"` for one line per preset.

## Bench results (2026-10-24, dark office, no court)

Galaxy S10e (RF8M40MT6AW), `detail4k30`, all clips 3840x2160, evidence in
`logs/verification-runs/manual-exposure-RF8M40MT6AW-20261024T164555/`:

| Preset | lockStatus | exposureTimeNs | iso | underexposed |
| --- | --- | --- | --- | --- |
| auto | auto | 30006000 | 3200 | - |
| 1/30 | locked | 33333000 | 2880 | false |
| 1/60 | locked | 16666000 | 3200 | true |
| 1/120 | locked | 8333000 | 3200 | true |

Galaxy S20 FE (RF8RA1C0ZKB, SM-G780G), same run, evidence in
`logs/verification-runs/manual-exposure-RF8RA1C0ZKB-20261024T182424/`:

| Preset | lockStatus | exposureTimeNs | iso | underexposed |
| --- | --- | --- | --- | --- |
| auto | auto | 29994234 | 3995 | - |
| 1/30 | locked | 33333333 | 3200 | true |
| 1/60 | locked | 16666667 | 3200 | true |
| 1/120 | locked | 8333333 | 3200 | true |

Galaxy S20 FE 5G (RFCNC0SVDFN, SM-G781B), evidence in
`logs/verification-runs/manual-exposure-RFCNC0SVDFN-20261024T184120/`: same
values as the SM-G780G above (auto 29994234 / ISO 3995; 1/30, 1/60, 1/120
locked at 33333333, 16666667, 8333333, ISO 3200, `underexposed` true).

S20 FE readout is ~28.7 ms (`rollingShutterSkewNs` 28739700) on both models.
Its auto mode goes above the manual ISO max (3995 vs 3200), so manual presets
need more light.

iPhone 12 Pro (iOS debug build, `detail4k30`), all clips 2160x3840 (portrait
4K), camera `built-in_video:5`, evidence in
`logs/verification-runs/manual-exposure-ios-20261024T185845/`:

| Preset | lockStatus | exposureTimeNs | iso | underexposed |
| --- | --- | --- | --- | --- |
| auto | auto | 24997000 | 2304 | - |
| 1/30 | locked | 33229000 | 1451 | false |
| 1/60 | locked | 16665000 | 2304 | true |
| 1/120 | locked | 8332000 | 2304 | true |

iOS run: `flutter run` on the phone, then drive the bridge at
`http://<phone LAN IP>:4762`. On this Mac, Python and the flutter tool are
denied macOS Local Network access (sockets fail with "No route to host";
curl works), so bridge discovery from `scripts/ios_capture_repro.py` finds
nothing. Grant Local Network access to the terminal app, or call the bridge
through curl.

S10e `rollingShutterSkewNs` = 15931210 (~16 ms readout) in every clip. All clips
reported `cameraId` 0 although the lens preference was `ultraWide`: check
which lens camera 0 is before the court run (see Known gaps).

## Known gaps

- Lens selection: a stored camera name wins over the lens preference, and
  `ultraWide` silently falls back to the first back camera when CameraX lists no
  ultra-wide. On the S10e the run used camera 0. Confirm the 0.5x lens on the
  preview before filming.

- The backend has to persist `captureSettings`; until it does, the values live
  in the app's local capture context and the upload request only.
- Locking is applied after recording starts too, because CameraX rebinds the
  session; the first ~0.5 s of a clip may still be auto exposed.
