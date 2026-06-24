# Evidence Run: Deploy HydraCam from remote MBA13 to all connected devices

- Source: user goal 2026-06-22 remote MBA13 deploy
- Slug: `mba13-all-connected-devices-redeploy`
- Verification tier: A (real-hardware)
- Status: blocked

## Acceptance Checks

- [x] MBA13 is reachable over Tailscale and has a native Flutter/Android/iOS dev environment inventoried
- [x] Remote published checkout is synced to GitHub branch head, with the deploy tree mirrored from the local working tree
- [x] Every MBA13-connected ADB-authorized Android device receives the current HydraCam build and launch/process/package proof
- [x] Every MBA13-connected paired iOS device receives the current signed HydraCam app or has an explicit signing/device blocker
- [x] Every non-deployed connected device has an explicit blocker recorded

## Device Matrix

- MBA13 host: `joss-macbook-air.tail6ce139.ts.net`, reachable through the dedicated `mba13` SSH key after updating `~/.ssh/authorized_keys`.
- Published Git checkout: `/Users/jose/src/work/hydracamv2-published`, reset to `origin/codex/hydracam-visual-makeover` at `8a9743c2c936be20d6d25dda7ed4d7040551a0d3`.
- Working-tree deploy mirror: `/Users/jose/src/work/hydracamv2-mba13-deploy`, updated by `rsync` from this Mac because the local branch is published but the worktree contains uncommitted app changes.
- Android deployed: Samsung S7 edge `9885e6503930304946`, Android 8/API 26.
- Android deployed: Samsung S10e `RF8M90QE7LX`, Android 12/API 31.
- iOS deployed: Jose Ramon's iPhone `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`, iOS 26.5, bundle `com.keepeyeonball`.
- Blocked: Samsung S10e `RF8M21J8XRT`, visible over USB but ADB state is `unauthorized`.
- Blocked: iPad 5 `0A947DBD-A462-5BAA-AB84-17F143D41619`, visible to CoreDevice but unpaired; `devicectl device install app` fails with `The device must be paired before it can be connected`.

## Evidence

- MBA13 toolchain readiness: `flutter doctor -v` passed for Flutter 3.44.1, Android SDK, Xcode 26.5, CocoaPods, Chrome, and network resources.
- MBA13 signing caveat: `security find-identity -p codesigning -v` reports zero valid identities, so the host can install signed iOS apps but cannot yet sign `com.keepeyeonball` natively.
- Android debug signing readiness: this Mac's debug keystore was copied to MBA13 so remote debug APK builds can update existing local-debug-key installs.
- Android APK built on MBA13 from the mirrored deploy tree: `build/app/outputs/flutter-apk/app-debug.apk`, SHA-256 `33d019a86384dc4ce1dcb47dc391eb4eb2984392dffd54ed3f3e03cdaa43631e`; `unzip -t` reported no compressed-data errors.
- Parallel Android install proof: both `adb install -r` calls returned `Success`, both apps launched with `am start`, and PIDs were observed.
- Samsung S7 edge proof: PID `25331`, `versionCode=18`, `versionName=1.4.0`, `lastUpdateTime=2026-06-22 18:38:36`.
- Samsung S10e `RF8M90QE7LX` proof: PID `22201`, `versionCode=18`, `versionName=1.4.0`, `lastUpdateTime=2026-06-22 18:38:22`.
- iPhone proof: `devicectl device install app` installed `com.keepeyeonball`, launch returned `Launched application with com.keepeyeonball bundle identifier`, installed app metadata showed `HydraCam 1.4.0 (18)`, and process PID `4193` was running `Runner.app/Runner`.
- Android foreground screenshots: `screenshots/9885e6503930304946-foreground.png`, `screenshots/RF8M90QE7LX-foreground.png`.
- Android foreground videos: `video/9885e6503930304946-foreground.mp4`, `video/RF8M90QE7LX-foreground.mp4`.
- Android logs: `device-logs/9885e6503930304946-deploy.log`, `device-logs/RF8M90QE7LX-deploy.log`, plus per-device logcat tails.
- Full command transcript: `commands.log`.

## Result

- Final disposition: blocked for all-connected completion, passed for every currently deployable remote hardware target.
- Deployed: two ADB-authorized Android phones and the paired iPhone.
- Not deployed: one Android phone blocked by ADB authorization prompt, and one iPad blocked by CoreDevice pairing.
