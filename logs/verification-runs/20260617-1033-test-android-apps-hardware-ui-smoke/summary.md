# Evidence Run: Android Hardware UI Smoke Via Test Android Apps Plugin

- Source: AGENTS.md#Validation Policy; docs/control/regular-evaluation-plan.md#Single Android Hardware Lane
- Slug: `test-android-apps-hardware-ui-smoke`
- Verification tier: A (real hardware)
- Status: blocked

## Acceptance Checks

- [x] A supported Android API 24+ target was identified: Samsung SM-G970F, Android 12/API 31, `RF8M90QE7LX`.
- [x] Host ADB path was corrected for this run by putting `/Users/jose/Library/Android/sdk/platform-tools` first in `PATH`.
- [x] Flutter Android Studio config was corrected from missing `/Applications/Android Studio 3.app` to installed `/Applications/Android Studio.app`.
- [x] HydraCam debug automation APK built and installed on `RF8M90QE7LX`.
- [ ] Setup and standby route screenshots passed through HydraCam `capture_screenshot`.

## Device Matrix

- Samsung SM-G970F, Android 12 (API 31), `RF8M90QE7LX`, setup and standby UI smoke target.

## Evidence

- `commands.log` records repo status, Flutter inventory, broken Homebrew `adb`, working SDK `adb`, Flutter config correction, build/install, route launch, bridge health, manual bridge probes, and unlock attempts.
- `summary.json` records the runner result: setup and standby both reached an identity-matched automation bridge, then failed on `POST /commands/capture_screenshot` timeout.
- `device-logs/RF8M90QE7LX/setup-result.json` and `device-logs/RF8M90QE7LX/standby-result.json` record per-route bridge health and failures.
- `screenshots/RF8M90QE7LX-system-screencap.png` is a raw ADB screenshot showing the device locked on the Android lock screen at 10:41.
- `device-logs/RF8M90QE7LX/manual-logcat-tail.txt` and `device-logs/RF8M90QE7LX/manual-logcat-after-bridge-timeout.txt` preserve logcat around the route launch and screenshot timeout.

## Result

- Final disposition: blocked by device lock.
- Superseded by
  `logs/verification-runs/20260617-1212-test-android-apps-hardware-ui-smoke-unlocked/`,
  which cleared the device lock with the local pattern unlock workflow and
  passed setup and standby route screenshots on `RF8M90QE7LX`.
- The corrected run built `build/app/outputs/flutter-apk/app-debug.apk`, installed it, granted available runtime permissions, forwarded `127.0.0.1:6700` to the automation bridge, and launched both `setup` and `standby`.
- `/healthz` returned `status=ok`, `automation=true`, and `automationTargetId=RF8M90QE7LX`; available commands were `capture_screenshot` and `set_role`.
- Both routes timed out on `capture_screenshot`; a direct valid JSON `curl` call to `capture_screenshot` also timed out after 120 seconds.
- Raw ADB `screencap` showed the device was locked. `dumpsys window` after ADB key/swipe unlock attempts still reported `isKeyguardShowing=true` and `mCurrentFocus=Window{... Bouncer}`. The device needs physical credential unlock before this route smoke can prove app UI.
- Continuation check on 2026-06-17 also found `isKeyguardShowing=true`, `mCurrentFocus=Window{... Bouncer}`, and HydraCam only behind the credential bouncer. Non-credential `wm dismiss-keyguard` and `input keyevent 82` did not clear the lock.
- Second continuation check on 2026-06-17 found the same state again: `RF8M90QE7LX` is ADB-visible and awake, but `dumpsys window` still reports `isKeyguardShowing=true` and `mCurrentFocus=Window{... Bouncer}`.

## Host Corrections Applied

- Flutter global config now points `android-studio-dir` at `/Applications/Android Studio.app`.
- `adb` now resolves to `/Users/jose/Library/Android/sdk/platform-tools/adb` in this shell; `/opt/homebrew/bin/adb` is no longer present. The repo command can still prefer SDK ADB explicitly for robustness:
  `PATH=/Users/jose/Library/Android/sdk/platform-tools:$PATH /usr/bin/python3 scripts/run_hardware_ui_e2e.py --device RF8M90QE7LX --route setup --route standby --run-dir <run-dir>`.
