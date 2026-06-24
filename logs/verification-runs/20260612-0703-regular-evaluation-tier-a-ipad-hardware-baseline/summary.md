# Evidence Run: Baseline regular evaluation Tier A physical iOS hardware lane

- Source: docs/control/regular-evaluation-plan.md#physical-ios-hardware-lane
- Slug: `regular-evaluation-tier-a-ipad-hardware-baseline`
- Verification tier: A (real-hardware)
- Status: blocked

## Acceptance Checks

- [x] Physical iPad launch was attempted through the mechanical capture repro.
- [x] The run recorded an actionable hardware/bridge blocker before photo/video
  capture could start.

## Device Matrix

- iPad (5), iPad7,5 / iOS 17.7.11,
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, single physical capture target.

## Evidence

- `commands.log`: `ios_capture_repro.py` exited 1 because the automation bridge
  was not discovered on `192.168.178.0/24:4762`.
- `flutter-run.log` and `device-logs/ipad-flutter-run.log`: Flutter built,
  installed, launched, and exposed a Dart VM Service on the iPad before bridge
  discovery failed.
- `device-logs/ipad-devicectl-details.json`: iPad was physical, booted, paired,
  wired, tunnel-connected, and Developer Mode enabled.
- `device-logs/ipad-devicectl-processes.log`: CoreDevice process streaming
  failed with `Couldn't get the message from the device`.
- `screenshots/ipad-screenshot-unavailable.txt`: Flutter reported physical
  screenshot capture unsupported for `iPad (5)`.
- `video/ipad-video-unavailable.txt`: physical iOS screen recording was not
  available from current CLI tooling during this blocked run.

## Result

- Final disposition: blocked.
- Next blocker: restore or explicitly probe the iPad automation bridge on a
  known LAN/link-local host before retrying photo/video capture.
