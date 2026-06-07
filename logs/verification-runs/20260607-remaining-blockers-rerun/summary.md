# Remaining Blockers Rerun

Date: 2026-06-07.

Scope: recheck the devices that still lacked passing one-by-one verification
after `logs/verification-runs/20260607-all-devices-one-by-one-rerun/`.

## Results

| Device | Check | Result | Evidence |
| --- | --- | --- | --- |
| Samsung S7 edge / Android 8 API 26 | `autoBack` + `dataSaver480p30` capture smoke | Failed. The app installed, launched, applied camera `0` and `dataSaver480p30`, initialized the camera, then photo capture timed out after 12 seconds. Live session stayed active with `photoCount: 0`; logcat shows Camera2 reopening and repeated `ExynosCamera3` wait timeouts. | `android-s7-dataSaver480p30/20260607_042039-s7-autoBack-dataSaver480p30-one-by-one/` |
| iPhone 12 Pro / iOS 26.4.2 | Direct `devicectl` app launch | Blocked. `devicectl` reported `Locked` and `Unable to launch com.vectorblanco.hydracam.dev because the device was not, or could not be, unlocked.` | `iphone12-launch-check/` |
| Xiaomi 2201116PG / Android 13 | Debug APK install | Blocked. `adb install -r build/app/outputs/flutter-apk/app-debug.apk` failed with `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`. | `xiaomi-install/adb-install.log` |

## Status

The full active goal remains incomplete. The remaining blockers are unchanged:
S7 fails even at the lowest profile, iPhone 12 Pro cannot be launched while
locked, and Xiaomi cannot be installed until the device-side install restriction
is cleared.
