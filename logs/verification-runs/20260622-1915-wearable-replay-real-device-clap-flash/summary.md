# Evidence Run: Run full physical wearable replay proof with Ray-Ban Meta, Galaxy Watch4, and clap/flash sync

- Source: docs/control/wearable-replay-integration-plan.md#full-hardware-evidence
- Slug: `wearable-replay-real-device-clap-flash`
- Verification tier: A (real-hardware)
- Status: blocked

## Acceptance Checks

- [x] Meta DAT GitHub Packages entitlement passes with GH_TOKEN from gh auth token
- [ ] Ray-Ban Meta is physically paired and a DAT POV/audio stream or rolling-buffer fallback is captured
- [ ] Galaxy Watch4 is paired, BODY_SENSORS is permitted, and Health Services HR plus motion samples are captured
- [ ] HydraCam session contains clap/flash calibration evidence with measured alignment <= 50 ms
- [ ] media-timeline replay renders POV angle, audio-on state, HR/motion overlays, markers, feedback cues, and pre-publish review state

## Device Matrix

- Ray-Ban Meta glasses: expected POV/audio source; not visible host-side because no reachable paired phone exposed a DAT session.
- Galaxy Watch4: expected HR/motion/marker source; no Wear OS ADB target was visible, so `BODY_SENSORS` could not be requested or verified.
- Jose Ramon iPhone 12 Pro candidate paired phone: CoreDevice listed `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A` as unavailable; Flutter reported code `-27`.
- iPad (5) candidate HydraCam camera device: CoreDevice listed `0A947DBD-A462-5BAA-AB84-17F143D41619` as unavailable; Flutter reported code `-27`.

## Evidence

- `commands.log` records baseline `git status`, bounded `flutter devices`, `adb devices -l`, CoreDevice inventory, ADB mDNS discovery, USB inventory, Bluetooth inventory, DAT network readiness, and Wear OS APK build output.
- `device-logs/inventory-dat-watch-build-transcript.log` mirrors the command transcript for the blocked hardware state.
- `screenshots/BLOCKED-no-physical-wearable-ui.txt` and `video/BLOCKED-no-physical-wearable-video.txt` are explicit blocker files; no real physical wearable UI or video could be captured.
- DAT entitlement passed with `GH_TOKEN="$(gh auth token)"`: `Android DAT GitHub Package access - HTTP 200`.
- `:wearable:assembleDebug` passed, so the Galaxy Watch4 APK is ready for install once a Wear OS target is visible.

## Result

- Final disposition: blocked. The external DAT package-access gate is open, but the physical Ray-Ban Meta stream, Galaxy Watch4 `BODY_SENSORS` permission/Health Services stream, clap/flash calibration, and media-timeline hardware replay could not run because no Android/Wear OS target was visible and the physical iOS devices were unavailable to Flutter/CoreDevice.
