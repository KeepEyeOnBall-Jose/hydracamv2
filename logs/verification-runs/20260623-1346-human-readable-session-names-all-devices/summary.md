# Evidence Run: Human-readable session names

- Source: docs/control/backlog-import.md#human-readable-session-names
- Slug: `human-readable-session-names-all-devices`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [x] Setup flow shows generated session naming controls; created/active sessions use readable display titles instead of GUID-primary UI.
- [x] Physical iPad capture proof shows `displayName` and `displayTitle` in automation snapshots while keeping `sessionGuid`.
- [x] Physical iPhone capture proof shows `displayName` and `displayTitle` in automation snapshots while keeping `sessionGuid`.
- [x] Physical Android setup/standby UI smoke captured screenshots and logs without overflow markers on SM G970F / RF8M21J8XRT.
- [x] Physical Android setup/standby UI smoke captured screenshots and logs without overflow markers on SM G960F / 29d816ac550b7ece.
- [x] Android emulator setup/standby UI smoke captured screenshots and logs without overflow markers on a clean API 36 AVD.
- [x] iOS simulator launch/integration test passed after accepting the native camera prompt.
- [x] Current Android debug build `versionCode=19` is installed on all three attached Android phones.
- [x] Durable emulator boot path repaired: Terminal.app launch, clean-data boot, and full `sys.boot_completed=1` verification passed.
- [ ] RF8M90QE7LX UI smoke remains blocked by secure keyguard state.
- [ ] TestFlight upload remains blocked until App Store Connect API key credentials are installed locally.

## Device Matrix

- SM G970F / Android 12 / RF8M21J8XRT: current APK installed; setup and standby UI smoke passed.
- SM G960F / Android 10 / 29d816ac550b7ece: current APK installed; setup and standby UI smoke passed.
- SM G970F / Android 12 / RF8M90QE7LX: current APK installed; UI smoke blocked by secure keyguard. `wm dismiss-keyguard` did not clear `ON_LOCKED`; the bridge now returns a bounded `Automation screenshot frame wait timed out` error with bridge logs and logcat.
- Medium Phone API 36 / Android 16 / emulator-5572: clean `-wipe-data` Terminal.app boot completed; current APK install plus setup and standby UI smoke passed.
- iPad (5) / iOS 17.7.11 / 8b406aa5c597eab4c4dfd9908f4a09b10a89ec63: physical capture proof passed.
- iPhone 12 Pro / iOS 26.5 / 00008101-000A68811E43001E: physical capture proof passed.
- iPhone 16 Pro simulator / iOS 18.4 / 6A2E7E6A-05F8-47D6-88AE-85E3434AC6D3: integration test passed after camera permission prompt was accepted.
- Hydra_Master_API34 and Pixel_7 Android AVDs: earlier detached/nohup attempts appeared briefly in ADB and disappeared before boot completion; this is superseded by the patched Terminal.app/full-boot path on `Medium_Phone_API_36`.

## Evidence

- Android screenshots:
  `android-rf8m21-current-rerun-timeout-guard/screenshots/RF8M21J8XRT-setup.png`,
  `android-rf8m21-current-rerun-timeout-guard/screenshots/RF8M21J8XRT-setup-after-scroll.png`,
  `android-rf8m21-current-rerun-timeout-guard/screenshots/RF8M21J8XRT-standby.png`,
  `android-29d816-current-rerun-timeout-guard/screenshots/29d816ac550b7ece-setup.png`,
  `android-29d816-current-rerun-timeout-guard/screenshots/29d816ac550b7ece-setup-after-scroll.png`,
  `android-29d816-current-rerun-timeout-guard/screenshots/29d816ac550b7ece-standby.png`.
- Android emulator screenshots:
  `android-emulator-working-path/20260623-clean-medium-phone-api36-patched-helper-current-install/screenshots/emulator-5572-setup.png`,
  `android-emulator-working-path/20260623-clean-medium-phone-api36-patched-helper-current-install/screenshots/emulator-5572-setup-after-scroll.png`,
  `android-emulator-working-path/20260623-clean-medium-phone-api36-patched-helper-current-install/screenshots/emulator-5572-standby.png`.
- RF8M90 locked-device evidence:
  `android-rf8m90-current-rerun-timeout-guard/summary.md`,
  `android-rf8m90-current-rerun-timeout-guard/device-logs/RF8M90QE7LX/setup-bridge-logs.json`,
  `android-rf8m90-current-rerun-timeout-guard/device-logs/RF8M90QE7LX/setup-logcat.txt`.
- iOS simulator screenshot:
  `ios-simulator-rerun/screenshots/iphone-16-pro-simulator-after-flutter-test.png`.
- iPad capture proof:
  `ios-ipad-capture/summary.json`,
  `ios-ipad-capture/automation-snapshots.json`.
- iPhone capture proof:
  `ios-iphone-capture-rerun/summary.json`,
  `ios-iphone-capture-rerun/automation-snapshots.json`.
- Android emulator startup logs:
  `../../emulator_5572.log`.
- Video artifact:
  `video/video-unavailable.txt` records why this Tier A video requirement was
  unavailable in the partial run.

## Result

- Final disposition: partial.
- Implementation passed local analyzer/tests, physical iPad capture proof,
  physical iPhone capture proof, two Android hardware UI smokes, a clean
  Android API 36 emulator UI smoke, and iOS simulator integration testing.
- The attached Android phones all accepted the current APK. RF8M90QE7LX remains
  the only Android UI-smoke gap because Android reports `ON_LOCKED` with focus
  on the keyguard bouncer.
- The emulator blocker is repaired by `scripts/boot_and_verify_emulators.py`
  with `--terminal-app --no-window --no-audio --no-boot-anim --wipe-data`,
  which waits for full Android boot completion before claiming success.
- Distribution artifact `build/ios/ipa/HydraCam.ipa` was rebuilt as
  `1.4.0+19` with SHA-256
  `da4e867b400e7236ebc9571fa190758723bd14288cbe480a6e23bce89f31016a`.
- TestFlight upload is blocked because no App Store Connect API key is present
  in the local environment. The release scripts now auto-source
  `~/.hydracam/secrets/app-store-connect.env` when that file exists.
