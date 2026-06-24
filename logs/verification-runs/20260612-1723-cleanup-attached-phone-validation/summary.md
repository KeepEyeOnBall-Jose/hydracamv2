# Cleanup Attached Phone Validation

- Status: `partial`
- Tier: `A` real hardware
- Run directory: `logs/verification-runs/20260612-1723-cleanup-attached-phone-validation`

## Scope

- Android hardware: `RF8M21J8XRT`, `RF8M90QE7LX`
- iOS hardware: `00008101-000A68811E43001E`
- iPad (5): visible to CoreDevice but unavailable, so not included.

## Static Gates

- `flutter analyze --no-pub`: passed after the gallery persistence fix.
- `flutter test --no-pub`: passed after the gallery persistence fix.
- `git diff --check`: passed after the gallery persistence fix.

## Code Change Made During Run

The first iPhone capture repro built, installed, launched, created a backend
session, and saved a JPEG to the iPhone app container, but `/commands/take_photo`
timed out before the automation handler returned. The Flutter log stopped after
`Photo saved to session path`, which placed the stall in gallery persistence.

`lib/services/gallery_persistence_service.dart` now bounds Photos permission and
gallery save operations with an 8 second timeout and keeps media in the session
directory if the native gallery side effect stalls. Regression coverage lives in
`test/services/gallery_persistence_service_test.dart`.

## Device Results

- Android debug APK rebuilt and installed on both Android phones.
- Android setup/standby hardware UI smoke passed on `RF8M21J8XRT`.
- Android setup/standby hardware UI smoke passed on `RF8M90QE7LX`.
- iPhone debug launch/capture repro passed after the gallery timeout fix.
- iPhone capture evidence: bridge `http://10.10.103.208:4762`, one photo, one video, recording stopped, trace file under `/var/mobile/...`.
- Current iOS Profile automation app built and installed on the iPhone.
- Warm-bridge prime passed for both Android phones and the iPhone.
- Three-phone role-switch rotations were blocked before rotation because Android LAN preflight could not resolve Wi-Fi IPs.

## Blocker

- `RF8M21J8XRT`: no `wlan0` IPv4; route to `1.1.1.1` used cellular `rmnet0` with source `10.190.80.29`.
- `RF8M90QE7LX`: no `wlan0` IPv4; route check returned `RTNETLINK answers: Network is unreachable` after airplane/Wi-Fi ADB toggles.

## Evidence

- Android screenshots: `screenshots/`
- Android logs: `device-logs/`
- Android video: `video/RF8M21J8XRT-cleanup-evidence.mp4`
- iPhone failed pre-fix repro: `ios-capture-repro/`
- iPhone passed post-fix repro: `ios-capture-repro-after-gallery-timeout/`
- Role-switch blocked run with warm-bridge proof: `three-phone-role-switch-explicit-ios-host/`
