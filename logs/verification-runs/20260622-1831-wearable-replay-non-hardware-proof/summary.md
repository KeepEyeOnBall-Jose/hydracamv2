# Evidence Run: wearable replay non-hardware proof

- Run id: `20260622-1831-wearable-replay-non-hardware-proof`
- Created at: `2026-06-22T16:36:49.386995+00:00`
- Status: passed
- Verification tier: non-hardware emulator/simulator/live-local-backend

## Acceptance Checks

- [x] HydraCam wearable model/service tests pass
- [x] Android emulator native mock bridge passes
- [x] iOS simulator native mock bridge passes
- [x] Wear OS module unit/build proof passes
- [x] media-timeline backend/frontend wearable replay tests pass
- [x] HydraCam-generated wearable manifest uploads to media-timeline
- [x] Replay page renders POV/HR/motion/sync/feedback/audio/review overlay

## Live Replay Proof

- Event/session: `hydracam-wearable-live-1782146206076001`
- Video id: `b0db1ea1-d08b-4603-8509-63a606e6f3d1`
- Replay URL: http://localhost:5173/events/hydracam-wearable-live-1782146206076001/videos/b0db1ea1-d08b-4603-8509-63a606e6f3d1
- Overlay text: `visibility POV replay Ray-Ban Meta Rolling Highlight Sync green player-live-1 HR Motion 1 markers 3 samples 1 calibration 2 feedback cues Audio on Pre-publish review`
- Failed responses: `0`
- Console issues: `0`

## Commands

- `flutter-analyze`: passed (8.373s, stdout `commands/flutter-analyze.stdout.txt`)
- `wearable-readiness`: passed (59.083s, stdout `commands/wearable-readiness.stdout.txt`)
- `wearable-readiness-mock`: passed (0.058s, stdout `commands/wearable-readiness-mock.stdout.txt`)
- `wearable-readiness-dat-offline`: passed (0.056s, stdout `commands/wearable-readiness-dat-offline.stdout.txt`)
- `wearable-flutter-service-tests`: passed (4.726s, stdout `commands/wearable-flutter-service-tests.stdout.txt`)
- `android-emulator-native-channel`: passed (141.186s, stdout `commands/android-emulator-native-channel.stdout.txt`)
- `ios-simulator-native-channel`: passed (157.362s, stdout `commands/ios-simulator-native-channel.stdout.txt`)
- `wear-os-module`: passed (1.187s, stdout `commands/wear-os-module.stdout.txt`)
- `media-timeline-backend-wearable-tests`: passed (1.431s, stdout `commands/media-timeline-backend-wearable-tests.stdout.txt`)
- `media-timeline-frontend-wearable-tests`: passed (1.418s, stdout `commands/media-timeline-frontend-wearable-tests.stdout.txt`)
- `wearable-live-upload-proof`: passed (2.305s, stdout `commands/wearable-live-upload-proof.stdout.txt`)

## Remaining Gates

- Meta DAT GitHub Packages entitlement for mwdat-core/mwdat-camera/mwdat-mockdevice
- Ray-Ban Meta physical pairing and DAT capture stream proof
- Galaxy Watch4 physical pairing, BODY_SENSORS permission, and Health Services stream proof
- Full real-device clap/flash evidence pack with media-timeline replay review
