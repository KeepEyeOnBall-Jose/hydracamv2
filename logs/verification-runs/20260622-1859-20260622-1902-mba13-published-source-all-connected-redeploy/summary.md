# Evidence Run: MBA13 published-source all-connected redeploy

- Source: goal: deploy HydraCam on all devices attached to MBA13 from published checkout
- Slug: `20260622-1902-mba13-published-source-all-connected-redeploy`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] MBA13 published checkout is at pushed commit `9b099044`; Android APK is rebuilt from that checkout; all three Android and both iOS physical devices are installed and launched concurrently; device logs are captured

## Device Matrix

- Android: Samsung S7 edge `9885e6503930304946`, Android 8/API 26.
- Android: Samsung S10e `RF8M21J8XRT`, Android 12/API 31.
- Android: Samsung S10e `RF8M90QE7LX`, Android 12/API 31.
- iOS: Jose Ramon's iPhone `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`, iOS 26.5.
- iOS: iPad 5 `0A947DBD-A462-5BAA-AB84-17F143D41619`, iPadOS 17.7.11.
- Host: MBA13 over Tailscale, Flutter 3.44.1 available at `/Users/jose/development/flutter/bin/flutter`, Xcode/CoreDevice available.

## Evidence

- GitHub branch `codex/hydracam-visual-makeover` was pushed to commit `9b09904442e44a59c7f66a5e8d8612860aeba5a1`.
- MBA13 published checkout `/Users/jose/src/work/hydracamv2-published` was reset to the same commit and reported a clean `git status -sb`.
- MBA13 built `/Users/jose/src/work/hydracamv2-published/build/app/outputs/flutter-apk/app-debug.apk` from that published checkout, SHA-256 `4857305bf517f4e3e3c829ff6cc5d6386666e2405029f1c44607c50f92696b09`.
- Final concurrent batch started all five targets at `2026-06-22T17:00:59Z`.
- Android batch proof:
  - `9885e6503930304946`: install `Success`, launch PID `29595`, `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 19:01:26`.
  - `RF8M21J8XRT`: install `Success`, launch PID `23501`, `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 19:01:15`.
  - `RF8M90QE7LX`: install `Success`, launch PID `24172`, `versionName=1.4.0`, `versionCode=18`, `lastUpdateTime=2026-06-22 19:01:15`.
- iOS batch proof:
  - iPhone `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`: installed `com.keepeyeonball`, launch PID `4329`, executable `Runner.app/Runner`.
  - iPad `0A947DBD-A462-5BAA-AB84-17F143D41619`: installed `com.keepeyeonball`, launch PID `21579`, executable `Runner.app/Runner`.
- Evidence files: `device-logs/published-source-redeploy/`, Android foreground captures in `screenshots/`, and Android short screen recordings in `video/`.
- Native-dev caveat: `security find-identity -p codesigning -v` on MBA13 still reports `0 valid identities found`; the remote host can build/deploy Android and install/launch signed iOS bundles, but cannot sign fresh iOS builds until an Apple signing identity/private key is added.

## Result

- Final disposition: passed for deployment on all currently attached physical devices. Remaining setup gap is remote iOS code signing identity.
