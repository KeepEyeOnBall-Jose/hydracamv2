# Evidence Run: Verify iOS icon-launchable Profile build

- Source: docs/control/status-and-roadmap.md#release-blockers
- Slug: `ios-icon-profile-launch`
- Verification tier: A (real-hardware)
- Status: prepared

## Acceptance Checks

- [ ] Debug launch remains available through flutter run or Xcode only
- [ ] Profile build installs on the physical iPhone
- [ ] App starts from the Home Screen icon or devicectl launch without Flutter tooling
- [ ] HydraCam reaches the first functional app screen, not the Flutter debug tooling message
- [ ] Startup evidence includes device model, OS, launch output, and device or app logs

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- `commands.log`: analyzer, focused tests, script syntax, fastlane syntax, Profile build/install, failed foreground launch, successful non-activating launch.
- `device-logs/devicectl-profile-launch.log`: foreground launch failed because SpringBoard reported the iPhone was locked.
- `device-logs/devicectl-profile-launch.json`: structured foreground launch failure with `BSErrorCodeDescription = Locked`.
- `device-logs/devicectl-profile-launch-no-activate.log`: no-tooling launch succeeded without activating the locked phone.
- `device-logs/devicectl-profile-launch-no-activate.json`: structured launch success, process ID `1172`, executable `Runner.app/Runner`.
- `device-logs/devicectl-processes-after-profile-launch.json`: process list after the non-activating launch includes `Runner.app/Runner` process ID `1172`.
- `device-logs/devicectl-processes-after-profile-launch.log`: command transcript for process list capture.
- `device-logs/devicectl-profile-install-first-failure.log`: first install attempt failed because a global `PRODUCT_BUNDLE_IDENTIFIER` xcodebuild override was applied to plugin frameworks, causing duplicate framework identifiers. The script/project config was corrected and the later install passed.
- `screenshots/foreground-capture-blocked.txt`: screenshot capture was blocked because the phone could not be foreground-launched while locked.
- `video/icon-launch-video-blocked.txt`: manual icon-launch video remains pending until the iPhone is unlocked.

## Baseline Debug Evidence

- Existing run: `logs/verification-runs/2026-06-06-iphone-personal-team-debug/run-summary.md`.
- Result: `flutter run -d 00008101-000A68811E43001E --debug --no-pub -t lib/main.dart` launched and attached to the Dart VM Service.
- Functional proof from that run: permissions granted, `SlaveScreen(isAutoMode=true)` loaded, master fallback started WebSocket port 4040, session ID 466/GUID f60e4a7a-ec8e-4897-8943-43dc0325e2d6 created, photo captured/saved/uploaded, and video recording started.
- Limitation: this was not a Home Screen icon launch and should not be used as proof that Debug builds can start standalone.

## Result

- Final disposition: partial.
- Profile build passed.
- Profile install passed for bundle ID `com.vectorblanco.hydracam.dev`.
- Standalone no-tooling process launch passed with `--no-activate`.
- Foreground/icon launch proof is still pending because the iPhone was locked, and SpringBoard denied activation.
