# Evidence Run: Validate iOS release/profile launch and capture readiness

- Source: docs/control/backlog-import.md#1-validate-ios-release-profile-launch-and-capture-readiness
- Slug: `ipad-runtime-screenshot-boundary-route-replacement`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Profile app launch reaches an identity-matched iPad automation bridge.
- [x] `capture_screenshot` works before and after runtime `set_role` to master.
- [x] Analyzer and focused widget/app-shell tests pass.

## Device Matrix

- iPad (5), iPad (6th generation) A1893 / iPad7,5, iOS 17.7.11.
- Flutter UDID / automation target ID:
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`.
- CoreDevice ID: `0A947DBD-A462-5BAA-AB84-17F143D41619`.
- Host used by runner: `169.254.193.202:4762`.

## Evidence

- `runner-ipad-warm-prime-updated/warm-bridge-prime.json`: Profile build,
  install, and standby launch passed on the connected iPad.
- `commands.log`: before the fix, the same flow failed with
  `Automation screenshot boundary is not mounted`; after the fix,
  `capture_screenshot` returned `status=ok` before and after `set_role`.
- `screenshots/ipad-standby-after-boundary-fix.png`: iPad-origin automation
  screenshot from the standby route.
- `screenshots/ipad-master-after-boundary-fix.png`: iPad-origin automation
  screenshot after runtime `set_role` into master.
- `device-logs/ipad-automation-logs.json`: persisted bridge/app logs from the
  updated iPad app.
- `video/ipad-master-after-boundary-fix-recording.mp4`: copied from the iPad
  app container after the post-`set_role` master route recorded one local video.
  `ffprobe` reports H.264 1920x1080 and 12.287 seconds.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub test/widget_test.dart
  test/camera_singleton_initialization_test.dart`: passed, including the new
  regression test that the automation screenshot boundary survives route
  replacement.
- `flutter test --no-pub`: full local test suite passed.

## Result

- Final disposition: passed. The screenshot boundary is now wrapped around the
  `MaterialApp` navigator instead of the removable home route, so runtime role
  replacement no longer unmounts the automation screenshot boundary.
