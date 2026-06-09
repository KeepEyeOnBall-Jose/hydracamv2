# Evidence Run: Validate iOS release/profile launch and capture readiness on connected iPad

- Source: docs/control/backlog-import.md#1-validate-ios-release-profile-launch-and-capture-readiness
- Slug: `ipad-physical-release-profile-smoke`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Connected physical iPad is visible to current tooling and recorded in the device matrix.
- [x] Profile app launch reaches an inspectable HydraCam runtime surface and identity-matched automation bridge.
- [x] iPad identity, screenshot, photo capture, video capture, and device logs are recorded.

## Device Matrix

- iPad (5), iPad (6th generation) A1893 / iPad7,5, iOS 17.7.11 21H461.
- Flutter UDID / automation target ID: `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`.
- CoreDevice ID: `0A947DBD-A462-5BAA-AB84-17F143D41619`.
- Host used by runner: `169.254.193.202:4762`.

## Evidence

- `runner-ipad-warm-prime-host/warm-bridge-prime.json`: `status=passed`; initial missing bridge warmed by Profile build/install/launch.
- `runner-ipad-single-capture/summary.json`: `status=passed`; one iPad master rotation, one capture target, no failures.
- `runner-ipad-single-capture/.../automation-snapshots.json`: session stages passed; `photoCount=1` after photo, `isRecording=true` after start, `videoCount=1` after stop.
- `screenshots/ipad-profile-standby.png`: iPad-origin automation screenshot of the launched standby surface.
- `screenshots/ipad-captured-photo.jpg`: copied from the iPad app container; EXIF reports Apple iPad (6th generation), iOS 17.7.11, 1920x1080.
- `video/ipad-captured-video.mp4`: copied from the iPad app container; ffprobe reports H.264 1920x1080, 29.98 fps, 2.135 seconds.
- `device-logs/ipad-single-capture-automation-snapshots.json` and `device-logs/ipad-single-capture-logs.json`: copied runner/device log artifacts.
- Follow-up finding: after runtime `set_role` to master, `/healthz` exposes master commands, but `capture_screenshot` returns `Automation screenshot boundary is not mounted`; the later full capture launch still passed.

## Result

- Final disposition: passed.
