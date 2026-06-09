# Evidence Run: Update iOS signing to jose@keepeyeonball.com lane and redeploy to iPad/iPhone/TestFlight

- Source: user request 2026-06-09
- Slug: `signing-jose-keepeyeonball-ios-redeploy`
- Verification tier: A (real-hardware)
- Status: blocked

## Acceptance Checks

- [x] iPad and iPhone deploy attempts are recorded with current signing state; TestFlight beta upload is attempted or blocked with exact credential/signing reason

## Device Matrix

- iPad (5) / iOS 17.7.11 / CoreDevice `0A947DBD-A462-5BAA-AB84-17F143D41619`
  / Flutter target `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` /
  deploy target.
- Jose Ramon's iPhone 12 Pro / iOS 26.5 / CoreDevice
  `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A` / Flutter wireless target
  `00008101-000A68811E43001E` / deploy target.

## Evidence

- `commands.log` records the signing config baseline, device inventory, Profile
  build settings, and both Profile build/install attempts.
- Profile build settings now resolve to `DEVELOPMENT_TEAM = 4RRY2QT7H8` and
  `PRODUCT_BUNDLE_IDENTIFIER = com.keepeyeonball`.
- iPad deploy command:
  `IOS_XCODE_DESTINATION_ID=8b406aa5c597eab4c4dfd9908f4a09b10a89ec63
  IOS_DEVICE=0A947DBD-A462-5BAA-AB84-17F143D41619
  DERIVED_DATA_PATH=build/ios-icon-profile-keepeyeonball-ipad
  scripts/ios_icon_launch_dev.sh`.
- iPhone deploy command:
  `IOS_XCODE_DESTINATION_ID=00008101-000A68811E43001E
  IOS_DEVICE=AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A
  DERIVED_DATA_PATH=build/ios-icon-profile-keepeyeonball-iphone
  scripts/ios_icon_launch_dev.sh`.
- Both deploy attempts failed before install with Xcode exit 65:
  `No Accounts: Add a new account in Accounts settings` and no
  `iOS Development` certificate with private key for team `4RRY2QT7H8`.
- `device-logs/` records CoreDevice lock and display state for both devices;
  both devices were reachable and unlocked. The blocker is local Mac/Xcode
  signing state, not device lock.
- No screenshots or video were captured because HydraCam never installed or
  launched under the Keepeyeonball signing lane.

## Result

- Final disposition: blocked on local Xcode account/certificate for team
  `4RRY2QT7H8`. TestFlight upload was not attempted because no signed IPA can be
  produced and no App Store Connect API key was found locally.
