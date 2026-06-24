# Evidence Run: Baseline regular evaluation Tier B simulator lane

- Source: docs/control/regular-evaluation-plan.md#quick-lanes
- Slug: `regular-evaluation-tier-b-simulator-baseline`
- Verification tier: B (emulator-simulator-e2e)
- Status: passed

## Acceptance Checks

- [x] iOS simulator launches HydraCam integration platform smoke without Flutter exceptions
- [x] Simulator screenshot and device logs are captured

## Device Matrix

- iPhone 16 Plus simulator, iOS 18.4,
  `5CF4A12E-A8B5-4285-AE86-407B9067CB5F`, single app instance.

## Evidence

- `commands.log`: `flutter test integration_test/platform_test.dart -d 5CF4A12E-A8B5-4285-AE86-407B9067CB5F` passed 5/5.
- `screenshots/iphone-16-plus-platform-smoke.png`: simulator screenshot after the smoke.
- `video/iphone-16-plus-platform-smoke.mp4`: short simulator screen recording.
- `device-logs/iphone-16-plus-last5m.log`: last five minutes of simulator logs.

## Result

- Final disposition: passed.
- Note: this is launch/UI/service-initialization evidence only; it is not camera
  or gallery proof.
