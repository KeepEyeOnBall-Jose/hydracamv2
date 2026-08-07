# Android auth-gate emulator smoke — 2026-08-07

Branch: `master-jose-2025` (current source, no code changes made). No Android
hardware attached; emulator-only proof per task instructions.

## Device under test

- Emulator: `Hydra_Master_API34` -> adb serial `emulator-5554`
- `sdk_gphone64_arm64`, Android 14 (API 34), `sys.boot_completed=1`
- Build: debug APK, `HYDRACAM_AUTOMATION=true` (built by
  `scripts/run_hardware_ui_e2e.py`), dev auto-login dart-defines
  `HYDRACAM_DEV_AUTO_LOGIN=true` /
  `HYDRACAM_DEV_AUTO_LOGIN_EMAIL=jose@keepeyeonball.com`.

## Gate 1: dev-auto-login restores session on current build — PASSED

Command:

```
python3 scripts/run_hardware_ui_e2e.py --device emulator-5554 \
  --dev-auto-login-email jose@keepeyeonball.com --include-emulators \
  --route setup --route standby \
  --run-dir logs/verification-runs/20260807-auth-smoke-emulator/gate1-dev-auto-login-retry
```

First attempt (`gate1-dev-auto-login/`) failed: automation bridge never
reported `capture_screenshot` in its command list within the health-check
window, logcat showed `Backend warm-up timed out.` — a one-off cold-start /
emulator network warm-up issue (confirmed emulator DNS/ICMP reachability to
`hydracam.azurewebsites.net` afterwards). Kept as evidence of the transient
failure. Re-run with `--skip-build --skip-install` against the same installed
APK passed cleanly on both routes.

Evidence (`gate1-dev-auto-login-retry/`):

- `summary.md`: `setup`: passed, `standby`: passed.
- `device-logs/emulator-5554/setup-logcat.txt:293` and
  `standby-logcat.txt:269`:
  `Log registered: {message: Development auto-login restored user jose@keepeyeonball.com., ...}`
- App reached main UI, not the login screen, on both routes:
  `screenshots/emulator-5554-setup.png` ("Prepare Camera" / placement
  preview), `screenshots/emulator-5554-standby.png` ("Automation standby").
- No Flutter overflow/exception markers in either logcat.

## Gate 2: process-death recovery — PASSED

Manual adb sequence (harness script has no kill/relaunch cycle):

```
adb -s emulator-5554 shell am kill com.amaia23.hydracam       # no-op: app was foreground, PID unchanged (Android by design)
adb -s emulator-5554 shell am force-stop com.amaia23.hydracam # process actually terminated (pidof empty)
adb -s emulator-5554 shell am start -n com.amaia23.hydracam/.MainActivity --es role standby --es automationTargetId emulator-5554
```

- Before kill: PID 12313, log line present
  (`device-logs/before-kill-logcat.txt`), `screenshots/before-kill.png`
  shows "Automation standby" main UI.
- `am kill com.amaia23.hydracam` did not terminate the process — expected
  Android behavior; `am kill` only reclaims cached/background processes and
  the app was foreground. Confirmed with `adb shell pidof`.
- `am force-stop com.amaia23.hydracam` did terminate it (`pidof` returned
  empty / exit 1).
- Relaunch produced a new PID (12453) and the same log line reappeared
  within 1s: `device-logs/after-relaunch-logcat.txt`:
  `Log registered: {message: Development auto-login restored user jose@keepeyeonball.com., ...}`
- `screenshots/after-relaunch.png` shows the same main UI restored, no login
  screen.
- `grep -n "FATAL EXCEPTION\|AndroidRuntime: FATAL\|ANR in\|Flutter fatal\|Unhandled Exception" after-relaunch-logcat.txt` → no matches (no crash, no ANR, no
  Flutter fatal).

## Corroboration (cheap, not primary evidence)

- `flutter analyze --no-pub` → `No issues found!` (`analyze.log`).
- `flutter test --no-pub test/services/auth0_service_test.dart
  test/services/user_service_test.dart
  test/services/session_manager_test.dart` → `All tests passed!` (61 tests,
  `test.log`).

## Deferred / bridge-limited (not attempted)

Logout and account-switch were **not** exercised. The in-app automation
bridge driven by `scripts/run_hardware_ui_e2e.py` only exposes
`capture_screenshot` and `set_role` commands — no arbitrary tap/navigation
command exists to reach the logout control in the running app. Doing this
via raw `adb shell input tap <x> <y>` coordinates would be fragile
(screen-size and layout dependent) and was explicitly ruled out by the task.
This needs either a new bridge command (e.g. `tap`/`logout`) or a
widget/integration test that drives `UserService.logout()` directly. Not
implemented here.

## Evidence paths

- `logs/verification-runs/20260807-auth-smoke-emulator/gate1-dev-auto-login/` (failed first attempt, kept as evidence)
- `logs/verification-runs/20260807-auth-smoke-emulator/gate1-dev-auto-login-retry/` (passing run)
- `logs/verification-runs/20260807-auth-smoke-emulator/gate2-process-death-recovery/`
- `logs/verification-runs/20260807-auth-smoke-emulator/analyze.log`
- `logs/verification-runs/20260807-auth-smoke-emulator/test.log`

Nothing in this pack was committed; it is left in the working tree per task
instructions.
