# Evidence Run: mba13 tailscale phone update deploy

- Source: user goal 2026-06-21 install current HydraCam updates on phones connected to mba13 over Tailscale
- Slug: `mba13-tailscale-phone-updates`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Remote MBA13 is reachable over Tailscale SSH and has a synced current checkout
- [x] Current HydraCam Android debug APK builds on MBA13
- [x] Every ADB-authorized phone connected to MBA13 receives the update, launches HydraCam, and has pid/package proof
- [x] Every non-updated connected phone has an explicit blocker recorded
- [x] The currently available iPhone connected to MBA13 receives the current signed Profile app and launches HydraCam

## Device Matrix

- José Ramón’s iPhone / iOS 26.5 / `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`: installed and launched `com.keepeyeonball`.
- Samsung S7 edge / Android / `9885e6503930304946`: installed and launched `com.amaia23.hydracam`.
- Samsung S10e / Android / `RF8M90QE7LX`: installed and launched `com.amaia23.hydracam`.

## Evidence

- MBA13 SSH target: `jose@joss-macbook-air.tail6ce139.ts.net`.
- Current checkout was synced to `/Users/jose/src/work/hydracamv2-mba13-deploy` without touching the MBA's dirty `/Users/jose/src/work/hydracamv2` checkout.
- MBA13 Android build passed: `flutter build apk --debug`, producing `/Users/jose/src/work/hydracamv2-mba13-deploy/build/app/outputs/flutter-apk/app-debug.apk` in 545.3s.
- MBA13-built APK SHA-256: `047deef7dda3f68d883ab42ccf1a34407bdd009d282aeb17bdf462ee8bd48032`.
- The initial in-place Android install failed on the then-authorized S10e `RF8M21J8XRT` with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`; signer inspection showed the installed app used this Mac's debug key, not the MBA13 debug key.
- A matching local-debug-key Android APK was built locally and copied to MBA13 as `/Users/jose/src/work/hydracamv2-mba13-deploy/build/app/outputs/flutter-apk/app-debug-local-signed.apk`.
- After regenerating the MBA13 ADB key, `9885e6503930304946` authorized as `SM_G935F`; MBA13 `adb install -r` succeeded, `am start` launched `com.amaia23.hydracam/.MainActivity`, `pidof` returned PID `10552`, and package metadata showed `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 14:12:43`.
- After the user accepted the USB debugging prompt, `RF8M90QE7LX` authorized as `SM_G970F`; MBA13 `adb install -r` succeeded, `am start` launched `com.amaia23.hydracam/.MainActivity`, `pidof` returned PID `13728`, and package metadata showed `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 14:15:50`.
- The resumed MBA13 iOS build path was made usable through generated Flutter config cleanup and `pod install`, but MBA13 itself cannot currently sign `com.keepeyeonball`: `security find-identity -p codesigning -v` reported zero valid identities, no local provisioning profiles were present, and Xcode rejected `javier@keepeyeonball.com`.
- A fresh local Profile build succeeded for `com.keepeyeonball`, team `4RRY2QT7H8`, signed on 2026-06-22 with `Apple Development: Jose Ramon Torregrosa Duran (4K56D5L8D9)`.
- The embedded provisioning profile is valid until 2027-06-09 and includes the attached iPhone UDID `00008101-000A68811E43001E`.
- The signed app was transferred to MBA13 at `/Users/jose/src/work/hydracamv2-mba13-deploy/build/ios-mba13-transfer-profile/Build/Products/Profile-iphoneos/Runner.app`.
- MBA13 `devicectl device install app` installed `com.keepeyeonball`.
- MBA13 `devicectl device process launch --terminate-existing com.keepeyeonball` reported `Launched application with com.keepeyeonball bundle identifier`.
- MBA13 installed-app metadata showed `HydraCam` version `1.4.0`, build `18`.
- MBA13 `devicectl device info processes` showed PID `2427` running `/private/var/containers/Bundle/Application/8160D96A-B593-4E5F-8477-8F704D659CC9/Runner.app/Runner`.
- MBA13 display proof showed the iPhone LCD backlight on and active, and lock-state proof showed the device unlocked since boot.
- No real screenshot or video file was captured: this `devicectl` surface exposed install, launch, app metadata, process, display, and lock-state proof, but no CLI screen capture/recording command.

## Result

- Final disposition: passed for the currently connected update set. MBA13 remote deploy/build path is established; the connected iPhone, S7 edge, and S10e are updated and running HydraCam. Remaining setup caveat: MBA13 cannot yet sign iOS builds natively until its Apple signing identity/provisioning profile issue is fixed.
