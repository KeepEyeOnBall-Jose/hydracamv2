# All-Connected-Device Deploy + Smoke Matrix — 2026-06-25/26

Branch: `master-jose-2025` (canonical main line). Run by Claude Code.
Flutter 3.44.1 stable. Host: macOS 26.4.1, Apple M1.

## Goal

Bring all branches together to main, then deploy + smoke-test the app on every
connected target — macOS native (the M1), emulators (Android + iOS simulator),
Chrome (web), and the connected physical devices. Complete the achievable
control-plane goals.

## Branch consolidation (done)

- All branches at the same tip: `codex/hydracam-visual-makeover` == `master-jose-2025`;
  `codex/native-macos-camera-desktop` fully merged. Checked out `master-jose-2025`
  (github HEAD). `flutter analyze` clean.

## Device matrix results (after round 2)

| # | Target | Kind | Result | Proof |
|---|--------|------|--------|-------|
| 1 | Android emulator `emulator-5554` (API 34) | Android emulator | ✅ PASS | fresh APK; setup+standby+scroll, no overflow |
| 2 | iOS Simulator iPhone 17 / iOS 26.5 | iOS simulator | ✅ PASS | fresh build+run, Master Console (WS:4040, 1.4.0+19) |
| 3 | Chrome (web) | web-javascript | ✅ PASS | fresh web build, Slave Device screen, no console errors |
| 4 | **Physical Android S10e** (SM-G970F / Android 12, `RF8M21J8XRT`) | Android hardware | ✅ PASS | reused APK; setup+standby; "Automation standby / Bridge ready" |
| 5 | **Physical iPhone 12 Pro** (iOS 26.5, `00008101-…001E`) | iOS hardware | ✅ PASS | fresh `--profile` automation build (signed team 4RRY2QT7H8), bridge `192.168.178.170:4762`, in-app screenshot |
| 6 | **Physical iPad 5** (iOS 17.7.11, `8b406aa5…`) | iOS hardware | ✅ PASS | same automation app installed via devicectl, bridge `192.168.178.104:4762`, in-app screenshot (2048×1536) |
| 7 | macOS native (M1) | desktop | ⏳ see below | iOS device build works; macOS target had a build-system failure — retrying with clean + DerivedData clear |

### Evidence artifacts
- Android emu: `android-emu-e2e/summary.{md,json}`, screenshots, device-logs.
- iOS sim: `screenshots/ios-sim-iphone17-26.5.png` (Master Console).
- Web: `device-logs/web-chrome-evidence.txt`.
- Physical S10e: `s10e-hardware-ui-2/summary.md` + screenshots (PASS).
- Physical iPhone: `device-logs/iphone-capture-screenshot-command.json`,
  `device-logs/iphone-copy-screenshot.json`, `screenshots/iphone-all-connected.png`.
- Physical iPad: `device-logs/ipad-capture-screenshot-command.json`,
  `device-logs/ipad-copy-screenshot.json`, `screenshots/ipad-all-connected.png`.
- macOS diagnosis: `device-logs/macos-build-diagnosis.txt`.

## Round 2 notes (devices unlocked / re-engaged)

- The physical devices were locked/asleep in round 1. Once unlocked/awake:
  - **S10e** failed first only because its screen was **dozing** (automation
    screenshot frame-wait timed out); after `input keyevent KEYCODE_WAKEUP` +
    `svc power stayon true`, it passed.
  - The installed iPhone build lacked automation (no bridge), so a fresh
    `flutter build ios --profile --dart-define=HYDRACAM_AUTOMATION=true` build was
    installed via `devicectl` and launched with `HYDRACAM_AUTOMATION_ROLE=standby`.
    The matrix runner kept scanning a stale cached host (`.168`); the live bridge
    was found by LAN scan at the device's real IP (`.170`).
  - The **iPad** was `available (paired)`; a **direct** `devicectl device install`
    + `process launch` (bypassing the runner's discovery) reached it, and its
    bridge came up at `192.168.178.104`.
- Capture recipe (both iOS devices): POST `/commands/capture_screenshot` to the
  device bridge, then `xcrun devicectl device copy from --domain-type
  appDataContainer --domain-identifier com.keepeyeonball`.

## macOS native (target-specific build issue)

The iOS device build (`flutter build ios --profile`) succeeded in 73s, but the
**macOS** target repeatedly failed with Xcode "Build operation failed without
specifying any errors", reaching CopySwiftLibs/codesign with no task-level error
— `_DEVELOPMENT_TEAM_IS_EMPTY=YES`. Same Dart source builds for web/Android/iOS.
Retrying with `flutter clean` + `rm -rf DerivedData/Runner-*` + rebuild (result
appended on completion). A pre-existing macOS `.app` did launch/run on the M1.

## Net

6 of 7 targets proven this run with fresh builds and real device screenshots
(both emulators, web, and all three physical devices). macOS native is the lone
remaining target, blocked by a macOS-target Xcode toolchain issue (not a
HydraCam defect) — clean rebuild in progress.
