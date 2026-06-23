# Physical Wearable Replay Rerun

- Status: blocked.
- Source: `docs/control/wearable-replay-integration-plan.md#full-hardware-evidence`.
- Verification tier: A, real hardware.
- Acceptance target: Ray-Ban Meta DAT stream, Galaxy Watch4 Health Services
  stream, physical clap/flash calibration, and media-timeline replay proof.

## Device Matrix

- Ray-Ban Meta: expected physical POV/audio source.
- Galaxy Watch4: expected physical heart-rate/motion/marker source.
- S10e `RF8M21J8XRT`: ADB-visible Android 12 paired-phone candidate.
- S10e `RF8M90QE7LX`: ADB-visible Android 12 paired-phone candidate; HydraCam
  automation screenshots timed out in the separate S10e UI proof.
- iPhone 12 Pro `00008101-000A68811E43001E`: Flutter-visible wireless iPhone,
  candidate paired phone.
- iPad 5 `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`: Flutter-visible wireless
  HydraCam device.

## Evidence

- `flutter devices --device-timeout 10`, `adb devices -l`, `adb mdns services`,
  `xcrun devicectl list devices`, and host Bluetooth inventory were recorded in
  `commands.log`.
- `python3 scripts/check_wearable_replay_readiness.py mock` passed.
- `python3 scripts/check_wearable_replay_readiness.py dat` passed.
- `GH_TOKEN="$(gh auth token)" python3 scripts/check_wearable_replay_readiness.py dat --check-network --timeout-seconds 15`
  passed the external DAT package-access check.
- Direct `./android/gradlew -p android :wearable:assembleDebug` failed under the
  host default JDK 26 with Android Gradle tooling incompatibility.
- `JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home ./android/gradlew -p android :wearable:assembleDebug`
  passed.
- `RF8M21J8XRT` Bluetooth manager evidence shows bonded Watch4 and RB Meta
  entries, but the sampled top-level Bluetooth state was disconnected.
- `RF8M90QE7LX` Bluetooth manager evidence did not show Watch4 or RB Meta bonded
  entries.
- Host ADB mDNS reported no discovered services, and no Wear OS ADB target was
  visible.

## Result

- Final disposition: blocked on active wearable stream reachability.
- The current blocker is no longer "no candidate phone visible": the S10e
  paired-phone candidate is visible, and `RF8M21J8XRT` has bonded wearable
  entries. The missing gate is a currently connected Ray-Ban Meta DAT stream and
  a reachable Galaxy Watch4 Health Services / Wear OS ADB path with permissions.
- No physical wearable screenshot/video was captured because the proof blocked
  before the stream/replay capture stage. Placeholder notes are present under
  `screenshots/` and `video/` so `scripts/evidence_pack.py check` records the
  blocked state explicitly.
- `python3 scripts/evidence_pack.py check logs/verification-runs/20260623-0335-wearable-replay-real-device-rerun`
  passed after finalization.
