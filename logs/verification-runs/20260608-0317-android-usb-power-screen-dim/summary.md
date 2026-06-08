# Evidence Run: Battery, storage, and network safety

- Source: docs/control/evidence-first-loop.md#default-priority-queue
- Slug: `android-usb-power-screen-dim`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Android screens are dimmed through scripts/android_screen_brightness.py and brightness state is recorded
- [x] ADB battery/power baseline is recorded for every visible Android target
- [x] Idle runtime evidence is collected before any wait-loop fix is proposed

## Device Matrix

- Samsung SM-G960F / Android 10 API 29 / `29d816ac550b7ece`: USB-attached slave, no active session.
- Samsung SM-G935F / Android 8.0 API 26 / `9885e6503930304946`: USB-attached slave, no active session.
- Samsung SM-G970F / Android 12 API 31 / `RF8M90QE7LX`: USB-attached master, three connected clients.

## Evidence

- Brightness status before/after: `commands.log`; all three Android devices report `screen_brightness=0` and manual mode.
- Raw one-minute battery/app CPU samples: `artifacts/android-power-samples.jsonl`.
- One-minute battery/app CPU summary: `artifacts/android-power-summary.json`.
- Follow-up camera-service samples: `artifacts/android-power-cameraserver-samples.jsonl`.
- Follow-up camera-service summary: `artifacts/android-power-cameraserver-summary.json`.
- Screenshots: `screenshots/29d816ac550b7ece.png`, `screenshots/9885e6503930304946.png`, `screenshots/RF8M90QE7LX.png`.
- Videos: `video/29d816ac550b7ece.mp4`, `video/9885e6503930304946.mp4`, `video/RF8M90QE7LX.mp4`.
- Device logs: `device-logs/*-logcat-tail.txt`, `device-logs/*-dumpsys-battery.txt`, `device-logs/*-dumpsys-power.txt`, `device-logs/*-top-threads.txt`.

## Result

- Final disposition: passed for screen dimming and monitoring. No Flutter camera lifecycle fix was applied in this run.
- `29d816ac550b7ece` charged strongly over USB: `current_now` raw mean `1190.75`, level `51`, HydraCam app CPU mean `2.02%` of one core, cameraserver `0%`.
- `9885e6503930304946` stayed low-battery but charging: `current_now` raw mean `273.25`, level `9`, HydraCam app CPU mean `1.70%` of one core. Its `cameraserver` averaged `13.83%` of one core and logcat repeatedly reported `ExynosCamera3 ... Wait to start reprocessing stream` / `wait timeout`.
- `RF8M90QE7LX` was master with three connected clients and slow USB charging: `current_now` raw mean `117.5`, level `37`, HydraCam app CPU mean `9.72%` of one core, cameraserver `0%`.
- Current hypothesis: the inefficient wait loop is not a generic Dart loop. The clearest problem is the S7 edge vendor camera stack stuck after a prior capture timeout; the master S10e also has expected role/network CPU while serving clients. The next fix candidate is timeout cleanup in `CameraService` for S7-style capture failures, verified by rerunning this monitor before and after camera-controller disposal on timeout.
