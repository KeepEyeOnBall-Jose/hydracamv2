# Evidence Run: Fix Android NDK and verify HydraCam Android permission/display build on devices

- Source: user request 2026-06-08
- Slug: `android-ndk-permission-display-device-check`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Default Android debug build uses the repaired NDK without hydracamNdkVersion override
- [x] Rebuilt debug APK installs on every visible supported Android device or records an explicit blocker
- [x] HydraCam launches on each installed Android device and evidence captures permission/display state

## Device Matrix

- Samsung SM-G960F, Android 10 API 29, `29d816ac550b7ece`,
  deploy/check: installed, launched, showed
  `Network: Wi-Fi (FRITZ!Box 6591 Cable TZ) | IP: 192.168.178.153`.
- Samsung SM-G935F, Android 8.0 API 26, `9885e6503930304946`,
  deploy/check: installed, launched, showed
  `Network: Wi-Fi (FRITZ!Box 6591 Cable TZ) | IP: 192.168.178.64`.
- Samsung SM-G970F, Android 12 API 31, `RF8M90QE7LX`,
  deploy/check: installed, launched, showed
  `Network: Wi-Fi (enable location for SSID) | IP: 192.168.178.160`.
  App location appops were allowed; Android Location Services were disabled.

## Evidence

- `commands.log` records NDK quarantine/reinstall, `source.properties`
  verification, default `flutter build apk --debug`, installs, launches,
  location/appops checks, screen recordings, UI dumps, and logcat capture.
- `screenshots/` contains launch screenshots for all three Android devices.
- `video/` contains short launch screen recordings for all three Android
  devices.
- `device-logs/` contains UI hierarchy dumps and logcat snapshots for all three
  Android devices.
- Tight logcat scan found no HydraCam fatal crash or ANR. Older Android logs
  include non-fatal Flutter embedding class lookup noise, but the app remained
  visible and usable in the captured UI.

## Result

- Final disposition: passed. The local SDK now has a complete
  `/Users/jose/Library/Android/sdk/ndk/28.2.13676358` install with
  `Pkg.Revision = 28.2.13676358`; the temporary incomplete NDK directories were
  removed after the successful reinstall.
