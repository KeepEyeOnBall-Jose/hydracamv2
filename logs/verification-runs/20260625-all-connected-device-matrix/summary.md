# All-Connected-Device Deploy + Smoke Matrix — 2026-06-25

Branch: `master-jose-2025` (canonical main line). Run by Claude Code.
Flutter 3.44.1 stable. Host: macOS 26.4.1, Apple M1.

## Goal

Per user request: bring all branches together to main, then deploy + smoke-test
the app on every currently-connected target — macOS native (the M1 itself),
emulators (Android + iOS simulator), Chrome (web), and the connected physical
devices. Complete the "easy" (achievable-now) control-plane goals.

## Branch consolidation (done)

- All three branches were already at the same tip `443a143b`:
  - `codex/hydracam-visual-makeover` == `master-jose-2025` (identical)
  - `codex/native-macos-camera-desktop` is fully merged into `master-jose-2025`
    (`git merge-base --is-ancestor` = true).
- Checked out `master-jose-2025` (github HEAD / canonical). Nothing to merge.
- Baseline: `flutter analyze` = clean (exit 0).

## Device matrix results

| # | Target | Kind | Build (fresh) | Launch/Run | UI proof | Result |
|---|--------|------|---------------|-----------|----------|--------|
| 1 | Android emulator `emulator-5554` (API 34) | Android emulator | APK exit 0 (196MB) | yes | setup + standby + scroll, no overflow | **PASS** |
| 2 | iOS Simulator iPhone 17 / iOS 26.5 | iOS simulator | xcodebuild exit 0 | yes (Master mode, WS:4040) | Master Console screenshot (1.4.0+19) | **PASS** |
| 3 | Chrome (web) | web-javascript | `flutter build web` exit 0 (15MB main.dart.js) | served :8080, HTTP 200 | Slave Device screen, **no console errors** | **PASS** |
| 4 | macOS native (M1) | desktop | **fails (env)** | pre-existing build ran (PID alive) | n/a | **BLOCKED (host Xcode)** |
| 5 | Physical iPhone 12 Pro / iOS 26.5 `00008101-…001E` | iOS hardware | n/a (app installed) | **denied — device LOCKED** | n/a | **BLOCKED (unlock)** |
| 6 | Physical iPad 5 / iOS 17.7.11 `8b406aa5…` | iOS hardware | n/a | asleep / xctrace OFFLINE | n/a | **BLOCKED (wake)** |

All targets use dev-auto-login `jose@keepeyeonball.com` to pass the login gate.

### Evidence artifacts
- Android: `android-emu-e2e/summary.{md,json}`, `android-emu-e2e/screenshots/*.png`
  (setup, setup-after-scroll, standby), `android-emu-e2e/device-logs/*`.
- iOS sim: `screenshots/ios-sim-iphone17-26.5.png` (full Master Console;
  shows the new human-readable session name "Squash match - 2026-06-25").
- Web: `device-logs/web-chrome-evidence.txt` (HTTP 200, rendered UI, no console errors).
- Physical iOS: `device-logs/physical-ios-blockers.txt`,
  `device-logs/iphone-warm-bridge-prime.json`.
- Build logs: `build-logs/*.log`.

## Blockers (require a human action; not app defects)

### macOS native — fresh build blocked by host Xcode build-system contention
`flutter build macos` fails in ~8s with Xcode "Build operation failed without
specifying any errors" — a build-**system** (XCBBuildService) failure, with NO
Dart/Swift/clang/link/codesign error and no "Killed". The identical Dart code
builds fresh for web, Android, and iOS simulator in this same session, so this
is environmental. Resident on the host during the run: a Virtualization.framework
VM (~1GB) and ~10 leaked `xcodebuildmcp` MCP-server node processes; load average
peaked at 16. A pre-existing macOS `.app` did launch and run on the M1 (process
alive), so the app is runnable — but a current-source macOS pass was not
achieved and is not claimed.
- To unblock: close the other Codex/Xcode/`xcodebuildmcp` sessions (or reboot),
  then `flutter build macos --debug` + relaunch. (For a headless in-app
  screenshot, build with `--dart-define=HYDRACAM_AUTOMATION=true`, launch with
  `HYDRACAM_AUTOMATION_ROLE=standby`, then POST `/commands/capture_screenshot`.)

### Physical iPhone — device LOCKED
`xcrun devicectl device process launch … com.keepeyeonball` reached the tunnel +
developer disk image, then iOS denied: *"Unable to launch com.keepeyeonball
because the device was not, or could not be, unlocked."* App is installed; iOS
forbids launching on a locked device.
- To unblock: unlock the iPhone (keep it unlocked), then rerun warm-prime +
  capture (commands in `device-logs/physical-ios-blockers.txt`).

### Physical iPad — asleep / offline
`devicectl` = `available (paired)` but `xctrace list devices` = OFFLINE; pings
(247ms wireless) but no bridge (app not running). Wireless `devicectl` launch on
this iPad has historically timed out.
- To unblock: wake + unlock the iPad until `xctrace list devices` shows it under
  "== Devices ==", then rerun.

## Net

4 of the user's named categories proven this session: **Android emulator, iOS
simulator, and Chrome/web are fully green** (fresh build + live UI). macOS native
and both physical iOS devices are blocked by host/device environment (locked
device, asleep device, host Xcode saturation) — each needs one human action,
after which the remaining captures are a single rerun.
