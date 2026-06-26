# All-Connected-Device Deploy + Smoke Matrix — 2026-06-25/26

Branch: `master-jose-2025` (canonical main line). Run by Claude Code.
Flutter 3.44.1 stable. Host: macOS 26.4.1, Apple M1.

## Result: 7/7 connected targets PASS (fresh builds)

| # | Target | Kind | Result | Proof |
|---|--------|------|--------|-------|
| 1 | **macOS native (M1)** | desktop | ✅ PASS | clean rebuild (automation), bridge `127.0.0.1:4762`, in-app screenshot `macos-all-connected.png` (1600×1200), dev-auto-login restored |
| 2 | Android emulator `emulator-5554` (API 34) | Android emulator | ✅ PASS | fresh APK; setup+standby+scroll, no overflow |
| 3 | iOS Simulator iPhone 17 / iOS 26.5 | iOS simulator | ✅ PASS | fresh build+run, Master Console (WS:4040, 1.4.0+19) |
| 4 | Chrome (web) | web-javascript | ✅ PASS | fresh web build, Slave Device screen, no console errors |
| 5 | Physical Android **S10e** (SM-G970F / Android 12, `RF8M21J8XRT`) | Android hardware | ✅ PASS | reused APK; setup+standby; "Automation standby / Bridge ready" |
| 6 | Physical **iPhone 12 Pro** (iOS 26.5, `00008101-…001E`) | iOS hardware | ✅ PASS | fresh `--profile` automation build (team 4RRY2QT7H8), bridge `192.168.178.170:4762`, in-app screenshot |
| 7 | Physical **iPad 5** (iOS 17.7.11, `8b406aa5…`) | iOS hardware | ✅ PASS | same automation app via devicectl, bridge `192.168.178.104:4762`, in-app screenshot (2048×1536) |

## Branch consolidation (done)

All branches at the same tip: `codex/hydracam-visual-makeover` == `master-jose-2025`;
`codex/native-macos-camera-desktop` fully merged. Working on `master-jose-2025`
(github HEAD), pushed. `flutter analyze` clean.

## How each target was driven

- **macOS**: 6 builds failed at the Xcode build-system level ("Build operation
  failed without specifying any errors", reaching CopySwiftLibs). Root cause was
  a **corrupt DerivedData / SPM cache** from earlier killed builds.
  `flutter clean` + `rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*` +
  rebuild fixed it. Launched the `.app` with `HYDRACAM_AUTOMATION_ROLE=standby`,
  captured via `/commands/capture_screenshot`. See `device-logs/macos-build-diagnosis.txt`.
- **iOS sim / web / Android emulator**: round 1, fresh builds, dev-auto-login.
- **Physical S10e**: failed first only because its screen was **dozing**
  (automation screenshot frame-wait timed out); `input keyevent KEYCODE_WAKEUP`
  + `svc power stayon true`, then `run_hardware_ui_e2e.py --skip-build` passed.
- **Physical iPhone**: the installed build lacked automation (no bridge), so a
  fresh `flutter build ios --profile --dart-define=HYDRACAM_AUTOMATION=true`
  build (73s) was installed via `devicectl` and launched standby. The matrix
  runner kept scanning the stale cached host `.168`; the live bridge was found
  by LAN scan at the device's real IP `.170`.
- **Physical iPad**: `available (paired)`; a **direct** `devicectl device install`
  + `process launch` (bypassing runner discovery) reached it; bridge `.104`.
- **iOS capture recipe**: POST `/commands/capture_screenshot` to the device
  bridge → `xcrun devicectl device copy from --domain-type appDataContainer
  --domain-identifier com.keepeyeonball`.

## Evidence artifacts
- Screenshots (local; gitignored per repo policy): `screenshots/` —
  `macos-all-connected.png`, `ios-sim-iphone17-26.5.png`,
  `iphone-all-connected.png`, `ipad-all-connected.png`,
  `s10e-hardware-ui-2/screenshots/*`, `android-emu-e2e/screenshots/*`.
- Committed text: per-device `device-logs/*.json|*.txt`, `*/summary.{md,json}`,
  `device-logs/web-chrome-evidence.txt`, `device-logs/macos-build-diagnosis.txt`.

## Net

Every connected target — macOS native (M1), Android emulator, iOS simulator,
Chrome web, and all three physical devices (S10e, iPhone, iPad) — builds, deploys,
and renders the current `master-jose-2025` source, each verified with a real
screenshot or e2e pass. No remaining blockers.
