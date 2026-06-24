# Evidence Run: Continue MBA13 all-connected deploy after RF8M21 authorization

- Source: active goal continuation 2026-06-22
- Slug: `mba13-rf8m21-and-ipad-continuation`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Newly ADB-authorized RF8M21J8XRT receives the current MBA13-built HydraCam APK and launch/process/package proof
- [x] iPad pairing/install state is rechecked with current MBA13 CoreDevice output
- [x] iPad is paired through `xcrun devicectl manage pair`, installed, and launched
- [x] All five physical hardware targets are redeployed in one concurrent MBA13 batch

## Device Matrix

- Android: Samsung S7 edge `9885e6503930304946`, Android 8/API 26.
- Android: Samsung S10e `RF8M21J8XRT`, Android 12/API 31.
- Android: Samsung S10e `RF8M90QE7LX`, Android 12/API 31.
- iOS: Jose Ramon's iPhone `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`, iOS 26.5.
- iOS: iPad 5 `0A947DBD-A462-5BAA-AB84-17F143D41619`, iPadOS 17.7.11, hardware UDID `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`.
- Host: MBA13 `joss-macbook-air.tail6ce139.ts.net`, Flutter 3.44.1, Android SDK available, Xcode/CoreDevice available.

## Evidence

- Source/build artifact: MBA13 APK `/Users/jose/src/work/hydracamv2-mba13-deploy/build/app/outputs/flutter-apk/app-debug.apk`, SHA-256 `33d019a86384dc4ce1dcb47dc391eb4eb2984392dffd54ed3f3e03cdaa43631e`.
- `RF8M21J8XRT` individual recovery deploy: `adb install -r` returned `Success`, app launched, PID `20461`, package `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 18:44:24`.
- `RF8M21J8XRT` artifacts: `screenshots/RF8M21J8XRT-foreground.png`, `video/RF8M21J8XRT-foreground.mp4`, `device-logs/RF8M21J8XRT-logcat.txt`.
- iPad pairing: `xcrun devicectl manage pair --device 0A947DBD-A462-5BAA-AB84-17F143D41619` returned `available (paired)`.
- iPad install/launch: `devicectl device install app` installed `com.keepeyeonball`; `devicectl device process launch` returned JSON success with PID `21573` in the first relaunch and PID `21576` in the final concurrent redeploy.
- Final concurrent redeploy batch: started all five targets at `2026-06-22T16:49:48Z` and completed at `2026-06-22T16:50:19Z`.
- Final Android batch proof:
  - `9885e6503930304946`: install `Success`, launch PID `27511`, `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 18:50:14`.
  - `RF8M21J8XRT`: install `Success`, launch PID `22194`, `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 18:50:03`.
  - `RF8M90QE7LX`: install `Success`, launch PID `23250`, `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 18:50:02`.
- Final iOS batch proof:
  - iPhone `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`: installed `com.keepeyeonball`, launch PID `4260`, executable `Runner.app/Runner`.
  - iPad `0A947DBD-A462-5BAA-AB84-17F143D41619`: installed `com.keepeyeonball`, launch PID `21576`, executable `Runner.app/Runner`.
- Batch logs and CoreDevice JSON: `device-logs/all-hardware-redeploy/`.
- Full command transcript: `commands.log`.
- Remaining native-dev caveat: MBA13 still reports `0 valid identities found` for codesigning, so it is operational for Android builds, CoreDevice pairing/install/launch, and transferred signed iOS app deployment; it is not yet self-sufficient for signing new iOS builds without adding an Apple Development identity.

## Result

- Final disposition: passed for all currently connected physical hardware deployment.
- All five physical hardware targets attached to MBA13 were deployed in one concurrent batch and launched successfully.
- Remaining non-deployment setup gap: add Apple signing identity/provisioning to MBA13 if it must build and sign iOS apps locally instead of installing transferred signed builds.
