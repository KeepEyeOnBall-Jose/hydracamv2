# Camera Settings Device Matrix Rerun

Date: 2026-06-07.

Scope: rerun the local lens/profile implementation after batching automation
camera settings, fixing local automation session end, and bounding camera
capture waits with 12 second timeouts.

## Results

| Device | Target | Result | Evidence |
| --- | --- | --- | --- |
| Samsung S10e / Android 12 | `autoBack` + `standard1080p30` | Passed. One photo and one video saved to the session, video metadata logged `1920x1080, unknown fps, 4014 ms`, and automation session end returned inactive. | `android/20260607_032251-s10e-autoBack-standard1080p30-after-batch/` |
| Samsung S10e / Android 12 | `autoBack` + `standard1080p30` final current-build smoke | Passed after reinstalling the freshly built debug APK. Settings applied to camera `0`, one photo and one video saved, video metadata logged `1920x1080, unknown fps, 3866 ms`, and session completion returned inactive. | `android/20260607-final-s10e-autoBack-standard1080p30/20260607_035355-s10e-autoBack-standard1080p30-final-smoke/` |
| Samsung S10e / Android 12 | `autoBack` + `sport1080p60` | Failed with a bounded photo-capture timeout. The app applied `1080p at 60 fps`, selected camera `0`, and did not hit the earlier disposed-controller crash. Native logcat still shows Samsung/Exynos Camera3 request and buffer errors. | `android/20260607_033121-s10e-autoBack-sport1080p60-clean-timeout/` |
| Samsung S7 edge / Android 8 API 26 | `autoBack` + `standard1080p30` | Failed before photo with a bounded timeout after applying camera `0` and `1080p at 30 fps`. | `android/20260607_033406-s7-autoBack-standard1080p30-after-batch-timeout/` |
| Samsung S7 edge / Android 8 API 26 | `autoBack` + `compat720p30` | Failed before photo with a bounded timeout after applying camera `0` and `720p at 30 fps`. This shows the S7 problem is a baseline CameraX/device path issue, not only 1080p/60. | `android/20260607_033527-s7-autoBack-compat720p30-after-batch-timeout/` |
| Physical iPad / iOS 15.6.1 | `autoBack` + `standard1080p30` | Passed. One photo and one video saved; recording returned false after stop. Saved-video metadata is still unavailable on this iOS run. | `ipad-autoBack-standard1080p30-after-ios-metadata/` |
| iPhone 12 Pro / iOS 26.4.2 | `ultraWide` + `sport1080p60` | Blocked. Flutter built and signed the debug app, then Xcode timed out starting the debug session. A direct `devicectl` launch failed because the phone was locked. The automation bridge was never discovered. | `iphone12-ultraWide-sport1080p60-after-fixes/` |
| Xiaomi 2201116PG / Android 13 | debug APK install | Blocked by device policy/user confirmation. Fresh retry reports `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`. | `xiaomi-2201116pg-install-block/adb-install-rerun.log` |
| macOS | `autoBack` + `standard1080p30` mock/controller path | Passed. Mock photo/video controller flow completed. | `macos-standard1080p30-after-fixes/` |

## Open Acceptance Gap

The original acceptance target remains open: iPhone 12 Pro ultra-wide
1080p60/4K30 and Samsung S7 rear-wide 1080p60/4K30 have not passed with actual
width/height/fps metadata. Current code exposes and applies the settings, but
the device matrix shows target-specific runtime blockers that need follow-up.
