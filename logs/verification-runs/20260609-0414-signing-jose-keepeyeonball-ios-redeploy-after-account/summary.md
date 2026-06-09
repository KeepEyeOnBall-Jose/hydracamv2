# Evidence Run: Continue Keepeyeonball iOS signing deployment after Xcode account update

- Source: user confirmed account update 2026-06-09
- Slug: `signing-jose-keepeyeonball-ios-redeploy-after-account`
- Verification tier: A (real-hardware)
- Status: blocked

## Acceptance Checks

- [x] iPad and iPhone Profile build/install/launch are retried after account update and TestFlight readiness is checked

## Device Matrix

- iPad 5 / iOS 17.7.11: CoreDevice
  `0A947DBD-A462-5BAA-AB84-17F143D41619`, Flutter target
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`.
- iPhone 12 Pro / iOS 26.5: CoreDevice
  `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`, Flutter target
  `00008101-000A68811E43001E`.

## Evidence

- Xcode account state now includes team `4RRY2QT7H8` and Apple Development
  certificate `Apple Development: Jose Ramon Torregrosa Duran (4K56D5L8D9)`.
- `flutter build ios --profile --dart-define=HYDRACAM_AUTOMATION=true
  --dart-define=HYDRACAM_AUTOMATION_PORT=4762 -t lib/main.dart` built
  `build/ios/iphoneos/Runner.app` for bundle `com.keepeyeonball`.
- iPad install and launch succeeded through `devicectl`, but `/healthz` timed
  out on `169.254.193.202:4762` and `192.168.178.104:4762`, and discovery
  failed on `192.168.178.0/24` plus `169.254.193.0/24`.
- iPhone install and launch succeeded through `devicectl`; `/healthz` passed at
  `http://192.168.178.168:4762` with target
  `00008101-000A68811E43001E`.
- iPhone automation screenshot copied to
  `screenshots/iphone-keepeyeonball-standby.png`.
- `flutter build ipa --release --export-method app-store` passed and produced
  `build/ios/ipa/HydraCam.ipa`.
- `build/ios/ipa/DistributionSummary.plist` reports `Cloud Managed Apple
  Distribution`, team `4RRY2QT7H8`, profile `iOS Team Store Provisioning
  Profile: com.keepeyeonball`, and `beta-reports-active=true`.
- No local `APP_STORE_CONNECT_API_KEY_PATH`, `AuthKey_*.p8`, or
  `FASTLANE_SESSION` was found for TestFlight upload.

## Result

- Final disposition: blocked on iPad automation bridge readiness and App Store
  Connect upload credentials. Keepeyeonball local development signing,
  iPhone Profile automation deployment, and App Store IPA export are working.
