# All Devices One-by-One Rerun

Date: 2026-06-07.

Scope: rerun current HydraCam build evidence one device at a time across the
available Android, iOS, iOS simulator, and macOS targets. Chrome/web was not in
scope for this mobile/macOS request.

## Device Matrix

| Device | Run | Result | Evidence |
| --- | --- | --- | --- |
| macOS | `autoBack` + `standard1080p30` mock/controller repro | Passed. Automation bridge ran on `127.0.0.1`, mock photo/video capture completed, and the script reported no failures. | `macos-standard1080p30/` |
| iPhone 16 Plus simulator / iOS 18.4 | `autoBack` + `standard1080p30` launch/camera repro | Failed as expected for capture proof: the app launched and automation bridge started, but Flutter reported no available cameras for photo/video. | `ios-simulator-standard1080p30/flutter-run.log` |
| iPad / iOS 15.6.1 | `autoBack` + `standard1080p30` physical capture repro | Passed on clean bridge discovery. Bridge URL was `http://192.168.178.104:4762`, trace path was `/var/mobile/...`, one photo and one video were saved, recording returned false, and video metadata was unavailable. | `ipad-autoBack-standard1080p30-clean-bridge/` |
| iPhone 12 Pro / iOS 26.4.2 | `ultraWide` + `sport1080p60` physical capture repro | Blocked. After stopping other bridges, Flutter built and entered Xcode install/launch but no automation bridge was discovered. Direct `devicectl` launch failed because the phone was locked. | `iphone12-ultraWide-sport1080p60-clean-bridge/` |
| Samsung S10e / Android 12 | `autoBack` + `standard1080p30` physical capture repro | Passed. Debug APK installed, settings applied to camera `0`, one photo and one video saved, metadata logged `1920x1080, unknown fps`, and session completion returned inactive. | `android-s10e-standard1080p30/20260607_040609-s10e-autoBack-standard1080p30-one-by-one/` |
| Samsung S7 edge / Android 8 API 26 | `autoBack` + `compat720p30` physical capture repro | Failed before photo completion. Orchestrator timed out waiting for `photo-saved`; logcat tail shows repeated `ExynosCamera3` reprocessing wait timeouts. | `android-s7-compat720p30/20260607_040733-s7-autoBack-compat720p30-one-by-one/` |
| Xiaomi 2201116PG / Android 13 | debug APK install | Blocked before app launch. `adb install -r` failed with `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`. | `android-xiaomi-install/adb-install.log` |

## Invalidated Artifacts

The first iPad and iPhone auto-discovery attempts in this directory are not
valid iOS proof:

- `ipad-autoBack-standard1080p30/` discovered `http://192.168.178.160:4762` and
  recorded an Android `/data/user/0/...` trace path, so it was actually reading
  the Samsung S10e bridge.
- `iphone12-ultraWide-sport1080p60/` also discovered the Samsung S10e bridge.
  The clean rerun is `iphone12-ultraWide-sport1080p60-clean-bridge/`.

After those invalid attempts, Android app instances were force-stopped and
bridge discovery was rerun cleanly for iPad and iPhone.

## Completion Status

The full active goal is not complete. Current evidence proves macOS, physical
iPad, and Samsung S10e have one-by-one smoke coverage. The iOS simulator is
launchable but not a camera-capture target. The iPhone 12 Pro, Samsung S7 edge,
and Xiaomi remain unverified for successful capture because of current external
or device-specific blockers.
