# Evidence Run: Rerun physical wearable replay proof after phone connection

- Source: docs/control/wearable-replay-integration-plan.md#full-hardware-evidence
- Slug: `wearable-replay-real-device-phone-connected`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [x] Connected Android phone inventory is captured
- [x] Meta DAT entitlement passes with GH_TOKEN from gh auth token
- [x] Ray-Ban Meta pairing/DAT source is detected or a concrete pairing blocker is recorded
- [x] Galaxy Watch4 Wear OS debug/BODY_SENSORS path is detected or a concrete permission blocker is recorded
- [x] A real clap/flash wearable replay pack is captured or blocked on a specific missing device capability

## Device Matrix

- SM G960F `29d816ac550b7ece`, Android 10/API 29: visible candidate HydraCam phone.
- SM G970F `RF8M21J8XRT`, Android 12/API 31: active paired wearable phone. Bluetooth reports connected `Watch4 von Jose Ramon`, connected `RB Meta 00D5`, `com.facebook.stella`, Samsung Watch Manager, Samsung Health Monitor, and HydraCam `com.amaia23.hydracam` `1.4.0`/`versionCode=19`.
- SM G970F `RF8M90QE7LX`, Android 12/API 31: visible candidate HydraCam phone; no active wearable pairing found.
- iPhone 12 Pro `00008101-000A68811E43001E`, iOS 26.5: visible candidate HydraCam camera/phone.
- iPad (5) `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, iOS 17.7.11: visible candidate HydraCam camera.
- Ray-Ban Meta glasses: physically nearby and actively connected to `RF8M21J8XRT` as `RB Meta 00D5`, but no real DAT stream was captured because HydraCam still exposes the mock/fallback bridge in this lane.
- Galaxy Watch4: physically nearby and actively connected to `RF8M21J8XRT` as `Watch4 von Jose Ramon`, but no Wear OS ADB target was visible, so `BODY_SENSORS` and Health Services streaming could not be proven.

## Evidence

- `commands.log` records connected Flutter/ADB/CoreDevice inventories, DAT network readiness, ADB mDNS, Android package state, Bluetooth pairing state, companion device associations, screenshot/video capture, logcat, and package versions.
- `screenshots/RF8M21J8XRT-current-screen.png` is a real screenshot from the active paired phone.
- `video/RF8M21J8XRT-phone-connected.mp4` is a short real screen recording from the active paired phone.
- `device-logs/RF8M21J8XRT-logcat-tail.txt` and `device-logs/commands-transcript.log` capture phone logs and the command transcript.

## Result

- Final disposition: partial. The physical phone, Ray-Ban Meta Bluetooth pairing, Galaxy Watch4 Bluetooth pairing, and DAT entitlement are proven. The full clap/flash wearable replay remains blocked on two concrete gaps: the Watch4 is not exposed as a Wear OS ADB/debug target for install plus `BODY_SENSORS`, and the HydraCam phone app still needs a real DAT SDK bridge before it can capture a physical Ray-Ban POV/audio stream instead of the current mock/rolling fallback lane.
