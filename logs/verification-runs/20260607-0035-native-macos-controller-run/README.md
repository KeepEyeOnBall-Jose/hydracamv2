# Native macOS Controller Run Verification

Date: 2026-06-07

Scope: Verify HydraCam can run natively on this Mac as a controller/debug app
with desktop webcam capture deferred and mocked.

## Changes Verified

- macOS startup no longer calls unsupported `permission_handler` methods.
- macOS defaults `masterShouldRecord` to false unless a stored preference exists.
- macOS camera operations use `CameraService` mock mode by default.
- macOS app bundle has privacy usage strings and sandbox entitlements for
  local-network, media, Photos, and location access.

## Commands

```bash
flutter test test/services/permission_service_test.dart
flutter test test/services/settings_service_test.dart
flutter test test/services/camera_service_failure_test.dart
flutter analyze
flutter build macos --debug
ruby -rtimeout -e 'timeout = Integer(ARGV.shift); Timeout.timeout(timeout) { system(*ARGV); exit($?.exitstatus || 0) } rescue Timeout::Error; warn "TIMEOUT after #{timeout}s: #{ARGV.join(" ")}"; exit 124' 12 build/macos/Build/Products/Debug/HydraCam.app/Contents/MacOS/HydraCam
ruby -rtimeout -e 'timeout = Integer(ARGV.shift); Timeout.timeout(timeout) { system(*ARGV); exit($?.exitstatus || 0) } rescue Timeout::Error; warn "TIMEOUT after #{timeout}s: #{ARGV.join(" ")}"; exit 124' 45 flutter run -d macos --debug --dart-define=HYDRACAM_AUTOMATION=true --dart-define=HYDRACAM_AUTOMATION_ROLE=master
codesign -d --entitlements :- build/macos/Build/Products/Debug/HydraCam.app
flutter test
git diff --check
plutil -lint macos/Runner/Info.plist macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements
bash -n script/build_and_run.sh
./script/build_and_run.sh --verify
```

## Results

- Focused tests: passed.
- Full `flutter test`: passed.
- `flutter analyze`: passed with no issues.
- `flutter build macos --debug`: passed and built
  `build/macos/Build/Products/Debug/HydraCam.app`.
- Launch check: passed. The app reached normal startup, generated/retrieved a
  device ID, initialized `CameraServiceSingleton`, navigated to `SlaveScreen`,
  and connected to an existing LAN master. The old
  `MissingPluginException(No implementation found for method requestPermissions
  on channel flutter.baseflow.com/permissions/methods)` did not recur.
- Controller launch check: passed. With automation role set to `master`, the app
  reached normal startup, started the automation bridge on port 4762, navigated
  to `MasterScreen`, and started the WebSocket server on port 4040. The bounded
  command exited by timeout because the GUI/debug session stayed open.
- Signed debug entitlements include app sandbox, JIT, network client/server,
  camera, audio input, location, and Photos library.
- `git diff --check`: passed.
- `plutil -lint`: passed for macOS plist and entitlement files.
- `script/build_and_run.sh --verify`: passed. The script built the macOS debug
  app, launched the bundle, confirmed a `HydraCam` process, and stopped it.

## Deferred

Real macOS webcam capture remains intentionally deferred. Local camera capture
uses mock media files for now so the Mac can serve as a controller/debug device.
