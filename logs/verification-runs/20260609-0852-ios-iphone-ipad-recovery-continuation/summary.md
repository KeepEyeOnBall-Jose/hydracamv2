# Evidence Run: Recover physical iPhone and iPad Profile app launch, bridge, and screenshot state

- Source: docs/control/status-and-roadmap.md#release-blockers
- Slug: `ios-iphone-ipad-recovery-continuation`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Physical iPhone launches `com.keepeyeonball` and answers an identity-matched automation bridge.
- [x] Physical iPad launches `com.keepeyeonball` and answers an identity-matched automation bridge.
- [x] Both physical iOS devices produce current screenshots.
- [x] Selected physical iPhone+iPad immediate role-switch proof passes with both devices on port `4762`.

## Device Matrix

- iPhone 12 Pro, iOS 26.5, Flutter ID `00008101-000A68811E43001E`, CoreDevice `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`, final bridge `http://192.168.178.168:4762`.
- iPad (6th generation), iOS 17.7.11, Flutter ID `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, CoreDevice `0A947DBD-A462-5BAA-AB84-17F143D41619`, final bridge `http://192.168.178.104:4762`.

## Root Cause

The iPad reached Dart and opened the automation bridge, but startup then stalled before `runApp()` because `PermissionService.requestAllPermissions()` could wait indefinitely on the platform permission request. In that state `/healthz` could briefly answer with no registered UI commands, and the app never reached the standby screen.

The fix bounds startup permission requests with an 8 second timeout. If the platform request stalls, startup logs the timeout, continues, and reaches the Flutter UI. The iPhone permission path completed normally; the iPad later completed normally after the patched reinstall.

## Evidence

- iPad timeout-fix logs: `device-logs/ipad-bridge-logs-timeoutfix-4762.json`
- iPhone timeout-fix logs: `device-logs/iphone-bridge-logs-timeoutfix-4762.json`
- iPad standby screenshot: `screenshots/ipad-recovery-timeoutfix.png`
- iPhone standby screenshot: `screenshots/iphone-recovery-timeoutfix.png`
- iPhone master screenshot: `screenshots/iphone-master-after-role-switch.png`
- iPad slave screenshot: `screenshots/ipad-slave-after-role-switch.png`
- Passed selected iPhone+iPad role proof: `device-logs/ios-two-device-immediate-role-switch-explicit-lan/summary.md`
- Physical iOS screen-video blocker note: `video/physical-ios-screen-video-blocker.txt`

## Result

Both physical iOS devices are patched, installed, launchable, and reachable on identity-matched bridges at port `4762`. The selected immediate role-switch proof passed with explicit LAN hosts, two rotations, and both devices becoming master once in `0.45s`.
