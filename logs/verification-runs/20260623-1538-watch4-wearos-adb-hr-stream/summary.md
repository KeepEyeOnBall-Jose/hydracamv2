# Galaxy Watch4 Wear OS ADB + Health Services stream proof

Run: `20260623-1538-watch4-wearos-adb-hr-stream`
Date: 2026-06-23

## What this advances

The prior wearable-replay blocker was "no Wear OS ADB target visible for
installing/granting `BODY_SENSORS`". That gate is now cleared on physical
hardware, and a real permission bug was found and fixed.

## Device

- Galaxy Watch4 `SM-R875F`, Wear OS build release `16`, API `36`,
  `ro.build.characteristics=nosdcard,watch`.
- Reached over wireless ADB at `192.168.178.117:41145` after pairing on
  `192.168.178.117:36139`.

## Steps proven

1. Wireless ADB pair + connect to the Watch4 (`adb pair` / `adb connect`).
2. Built `:wearable:assembleDebug` (JDK 17) and installed
   `com.amaia23.hydracam.wearable` on the physical watch.
3. Granted `BODY_SENSORS`, `ACTIVITY_RECOGNITION`, and
   `android.permission.health.READ_HEART_RATE`; all report `granted=true`.
4. Launched `WearMainActivity` on the watch and captured live status.

## Bug found and fixed

First launch showed:

```text
Health Services registration failed: Missing permissions:
[android.permission.health.READ_HEART_RATE]
```

The Wear OS module declared only legacy `BODY_SENSORS`. On Wear OS 5+/API 35+
the Health Services `MeasureClient` heart-rate stream additionally requires
`android.permission.health.READ_HEART_RATE`. Fix:

- `android/wearable/src/main/AndroidManifest.xml`: declare the health
  permission.
- `android/wearable/src/main/kotlin/com/amaia23/hydracam/wearable/WearMainActivity.kt`:
  add the permission string to `REQUIRED_SENSOR_PERMISSIONS`.

After rebuild/reinstall/grant, the status changed to:

```text
Health Services HeartRate availability: ACQUIRING
HR 0 bpm
Motion 0.03
Health Services + sensors
Samples 9
```

Registration now succeeds (no permission failure). Motion telemetry is live.

## Screenshots

- `screenshots/watch4-wearmain.png` — initial capture (screen slept, blank).
- `screenshots/watch4-wearmain-awake.png` — HR registration failure (pre-fix).
- `screenshots/watch4-wearmain-hr-granted.png` — HeartRate availability
  ACQUIRING (post-fix).

## Remaining gate

`HR 0 bpm` is expected with the watch off-body on a desk: Health Services
reports `ACQUIRING` and withholds BPM until skin contact. The only remaining
step for a non-zero HR sample is wearing the watch on a wrist during capture.
Motion stream and Health Services registration are both proven on hardware.
