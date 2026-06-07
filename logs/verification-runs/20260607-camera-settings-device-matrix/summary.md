# Camera Settings Device Matrix Re-Verification

Date: 2026-06-07

Scope: Re-test HydraCam camera lens/profile settings and single-device capture
on every currently visible target: macOS, iOS simulator, physical iPad,
physical iPhone 12 Pro, Samsung S10e, Xiaomi 2201116PG, and Samsung S7 edge.

## Shared Build and Test Baseline

- `flutter analyze`: passed.
- `flutter test`: passed.
- `flutter build apk --debug --dart-define=HYDRACAM_AUTOMATION=true`: passed.
- Prior non-automation compile checks for this feature also passed:
  `flutter build apk --debug`, `flutter build ios --debug --no-codesign`,
  and `git diff --check`.

## Device Results

| Device | Target settings | Result | Evidence |
| --- | --- | --- | --- |
| macOS 26.4.1 | `autoBack`, `standard1080p30` | Passed controller/mock-camera path: one photo and one video, recording false after stop. This does not prove real desktop webcam capture. | `macos-standard1080p30/summary.json`, `macos-standard1080p30/automation-snapshots.json` |
| iOS Simulator iPhone 16 Plus / iOS 18.4 | `autoBack`, `standard1080p30` | App launched and settings applied after camera/mic privacy grants, but simulator has no camera exposed to the Flutter camera plugin; capture failed with `No cameras available on this device`. | `ios-simulator-standard1080p30-after-privacy/flutter-run.log`, `ios-simulator-standard1080p30-after-privacy/xcodebuildmcp-screenshot.jpg` |
| Physical iPad / iOS 15.6.1 | `autoBack`, `standard1080p30` | Passed: selected `com.apple.avfoundation.avcapturedevice.built-in_video:0`, captured one photo and one video, queued both, recording false after stop. Video metadata helper returned unavailable. | `ipad-autoBack-standard1080p30/summary.json`, `ipad-autoBack-standard1080p30/automation-snapshots.json` |
| Physical iPhone 12 Pro / iOS 26.4.2 | `ultraWide`, `sport1080p60` | Blocked: app is installed, but two `devicectl` launches were denied because the device is locked. The Flutter launch path also did not expose the automation bridge while locked. | `iphone12-installed-apps-rerun.json`, `iphone12-devicectl-launch.log`, `iphone12-devicectl-launch-second.log`, `iphone12-ultraWide-sport1080p60-rerun/flutter-run.log` |
| Samsung S10e / Android 12 API 31 | `autoBack`, `sport1080p60` | Failed before photo: settings applied and camera initialized, then capture hung with Samsung/Exynos camera buffer and request errors. | `android/20260607_023637-s10e-autoBack-sport1080p60-rerun/settings-live.json`, `android/20260607_023637-s10e-autoBack-sport1080p60-rerun/session-live.json`, `android/20260607_023637-s10e-autoBack-sport1080p60-rerun/device-logs/s10e-logcat-tail.txt` |
| Samsung S10e / Android 12 API 31 | `autoBack`, `standard1080p30` | Partial pass: settings applied, one photo and one video captured, recorded metadata logged `1920x1080, unknown fps, 3966 ms`. The final manifest failed because session end left `isActive=true`. | `android/20260607_023947-s10e-autoBack-standard1080p30/settings-live.json`, `android/20260607_023947-s10e-autoBack-standard1080p30/session-live.json`, `android/20260607_023947-s10e-autoBack-standard1080p30/bridge-logs-live.json` |
| Xiaomi 2201116PG / Android 13 API 33 | install only | Blocked: APK install is user-restricted. Re-run produced `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`. | `xiaomi-2201116pg-install-block/adb-install-rerun.log` |
| Samsung S7 edge / Android 8 API 26 | `autoBack`, `sport1080p60` | Failed before photo: settings applied, selected camera `0`, then native Samsung/Exynos camera buffer timeouts/errors; no photo or video. | `android/20260607_024615-s7-autoBack-sport1080p60-rerun2/settings-live.json`, `android/20260607_024615-s7-autoBack-sport1080p60-rerun2/session-live.json`, `android/20260607_024615-s7-autoBack-sport1080p60-rerun2/device-logs/s7-logcat-tail.txt` |
| Samsung S7 edge / Android 8 API 26 | `autoBack`, `standard1080p30` | Failed before photo: baseline camera capture still stuck with native Camera3/Exynos output-buffer timeouts; no 4K30 run was meaningful after baseline failed. | `android/20260607_024916-s7-autoBack-standard1080p30/settings-live.json`, `android/20260607_024916-s7-autoBack-standard1080p30/session-live.json`, `android/20260607_024916-s7-autoBack-standard1080p30/device-logs/s7-logcat-tail.txt` |

## Current Blockers

- iPhone 12 Pro: unlock the phone and keep it awake, then rerun
  `ultraWide` + `sport1080p60` and `ultraWide` or `wide` + `detail4k30`.
- Xiaomi 2201116PG: enable install permission for ADB/USB debugging security or
  manually approve the install prompt, then rerun capture.
- Samsung S7/S10e: investigate native CameraX/Camera3 buffer timeouts after
  profile/lens reinitialization, especially S7 baseline capture and S10e 60 fps.
- iOS metadata: physical iPad capture passed, but the saved-video metadata hook
  returned unavailable; fix before claiming actual iOS resolution/fps.
- Android session cleanup: S10e `standard1080p30` captured media, but
  `end_session` did not deactivate the local session in the automation path.

## Current Conclusion

The new settings system can persist and apply lens/profile choices on the
verified surfaces. Production support for the exact requested device matrix is
not yet proven: iPad and macOS controller paths passed, S10e 1080p30 partially
passed with actual 1080p metadata, but iPhone 12 Pro was locked, Xiaomi install
was blocked, and Samsung S7/S10e high-profile capture hit native camera errors.
