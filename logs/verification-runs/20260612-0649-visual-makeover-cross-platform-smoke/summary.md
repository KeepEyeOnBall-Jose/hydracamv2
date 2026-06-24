# Evidence Run: Visual makeover cross-platform device smoke

- Source: docs/control/hydracam-visual-makeover-plan.md
- Slug: `visual-makeover-cross-platform-smoke`
- Verification tier: C (multi-device-emulated-cluster)
- Status: partial

## Acceptance Checks

- [x] Connected Android hardware runs setup and standby routes with screenshots, logs, and no Flutter overflow markers: attempted, blocked by device-side install policy before UI route launch.
- [x] Android emulator runs setup and standby routes or records a concrete emulator/tooling blocker: attempted, blocker recorded after install/launch because automation commands were not registered.
- [x] Physical iPad installs or launches the current automation build and records screenshot/log evidence or a concrete device/tooling blocker: Profile build/install/launch passed; automation bridge was not reachable for screenshot capture.
- [x] iOS simulator launches the current app and records screenshot/log evidence or a concrete simulator/tooling blocker: passed through Flutter build/install/launch, bridge health, screenshot, logs, and video.
- [x] macOS target builds and launches the current app or records a concrete desktop blocker: passed through Flutter build/launch, bridge health, screenshot, process capture, and logs.

## Device Matrix

| Target | Identifier | Runtime | Result |
| --- | --- | --- | --- |
| Xiaomi 2201116PG | `575ecf2cbd24` | Android 13 / API 33 | Blocked at `adb install`: `INSTALL_FAILED_USER_RESTRICTED`, install canceled by user/device policy. |
| Medium_Phone_API_36 | `emulator-5554` | Android 16 / API 36 | APK installed and setup launched, but `/healthz` reported `automation=true` with `commands: []`; standby attempt then timed out clearing logcat. |
| iPad 6th generation | `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, CoreDevice `0A947DBD-A462-5BAA-AB84-17F143D41619` | iOS 17.7.11 | Profile build, install, and launch succeeded; display was active/unlocked, but automation bridge was not reachable on prior IPv4 hosts, LAN scan, or IPv6 host. |
| iPhone 16 Plus simulator | `5CF4A12E-A8B5-4285-AE86-407B9067CB5F` | iOS 18.4 simulator | Passed. Bridge `/healthz` returned `commands: ["capture_screenshot", "set_role"]`; screenshot, logs, and short video captured. |
| Local macOS | `macos-local` | macOS 26.4.1 25E253 | Passed. Debug app launched, bridge `/healthz` returned `commands: ["capture_screenshot", "set_role"]`; screenshot, process info, and unified logs captured. |

## Evidence

- Android hardware:
  - APK build succeeded: `flutter build apk --debug --dart-define=HYDRACAM_AUTOMATION=true`.
  - Route smoke: `android-hardware-ui/summary.md`.
  - Result: device refused install with `INSTALL_FAILED_USER_RESTRICTED`.
- Android emulator:
  - Route smoke: `android-emulator-ui/summary.md`.
  - Native screenshot: `screenshots/android-emulator-5554-native.png`.
  - Logcat: `device-logs/android-emulator-5554-logcat.txt`.
  - Result: launched but automation bridge never became command-healthy.
- Physical iPad:
  - Install proof: `device-logs/ipad-devicectl-install.json`.
  - Device state: `device-logs/ipad-displays.json`, `device-logs/ipad-lockstate.json`.
  - Bridge probes: `device-logs/ipad-192-168-178-104-healthz.json`, `device-logs/ipad-169-254-193-202-healthz.json`, `device-logs/ipad-ipv6-healthz.json`, plus `ipad-bridge-scan/`.
  - Result: launch succeeded, no reachable automation bridge for screenshot.
- iOS simulator:
  - System screenshots: `screenshots/ios-simulator-iphone16plus-setup.png`, `screenshots/ios-simulator-iphone16plus-setup-permissions-granted.png`.
  - Automation screenshot: `screenshots/ios-simulator-iphone16plus-setup-flutter.png`.
  - Bridge health: `device-logs/ios-simulator-iphone16plus-healthz.json`.
  - Logs and video: `device-logs/ios-simulator-iphone16plus-log.txt`, `video/ios-simulator-iphone16plus-setup.mp4`.
- macOS:
  - Automation screenshot: `screenshots/macos-setup-flutter.png`.
  - Bridge health: `device-logs/macos-local-healthz.json`.
  - Process/logs: `device-logs/macos-process.txt`, `device-logs/macos-hydracam-log.txt`.

## Result

- Final disposition: partial.
- Passing targets: iOS simulator and macOS.
- Blocked targets: physical Android install policy, Android emulator automation command registration, physical iPad bridge reachability after successful install/launch.
- Cleanup: Android emulator, macOS HydraCam app, and iOS simulator app were stopped after evidence collection.
