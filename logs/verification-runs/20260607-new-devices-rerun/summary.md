# 2026-06-07 New Devices Rerun

Fresh run after new physical devices were connected. All Android app instances
and stale local bridges were stopped before iOS auto-discovery so evidence is
attributed to the current device under test.

## Inventory

- Samsung SM-G960F / Android 10 / API 29 / serial `29d816ac550b7ece`
- Samsung SM-G935F / Android 8.0 / API 26 / serial `9885e6503930304946`
- Samsung SM-G970F / Android 12 / API 31 / serial `RF8M21J8XRT`
- Samsung SM-G970F / Android 12 / API 31 / serial `RF8M90QE7LX`
- iPad 5 / iOS 15.6.1 / Flutter id
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`
- iPhone 12 Pro / iOS 26.5 / Flutter id
  `00008101-000A68811E43001E`

## Results

| Device | Target | Result | Evidence |
| --- | --- | --- | --- |
| iPhone 12 Pro | `ultraWide` + `sport1080p60` | Passed debug automation capture: one photo, one video, recording stopped. Selected camera `com.apple.avfoundation.avcapturedevice.built-in_video:5`; target shown as `1080p at 60 fps`. Saved-video metadata was unavailable. | `iphone12pro-ultrawide-sport1080p60/summary.json`, `iphone12pro-ultrawide-sport1080p60/automation-snapshots.json` |
| iPhone 12 Pro | `ultraWide` + `detail4k30` | Passed debug automation capture: one photo, one video, recording stopped. Selected camera `com.apple.avfoundation.avcapturedevice.built-in_video:5`; target shown as `4K at 30 fps`. Saved-video metadata was unavailable. | `iphone12pro-ultrawide-detail4k30/summary.json`, `iphone12pro-ultrawide-detail4k30/automation-snapshots.json` |
| Samsung SM-G970F `RF8M21J8XRT` | `autoBack` + `standard1080p30` | Passed Android automation capture: one photo, one video, session ended. Native metadata logged `1920x1080, unknown fps, 3966 ms`. | `20260607_144440-new-rf8m21j8xrt-standard1080p30/summary.json`, `20260607_144440-new-rf8m21j8xrt-standard1080p30/RF8M21J8XRT/logs.json` |
| Samsung SM-G960F `29d816ac550b7ece` | `autoBack` + `standard1080p30` | Failed before photo save. App selected camera `0`, initialized, then CameraX `ImageCaptureException: Not bound to a valid Camera` occurred with explicit fps and again after fallback reinit without explicit fps. | `20260607_144222-new-g960f-standard1080p30/manual-after-failure/logs.json` |
| Samsung SM-G960F `29d816ac550b7ece` | `autoBack` + `compat720p30` | Failed before photo save with the same CameraX `ImageCaptureException: Not bound to a valid Camera` after initialization. | `20260607_144932-new-g960f-compat720p30/manual-after-failure/logs.json` |
| Samsung S7 edge `9885e6503930304946` | `autoBack` + `dataSaver480p30` | Failed before photo save. App selected camera `0`, initialized, then photo capture timed out after 12 seconds. Logcat shows repeated ExynosCamera3 wait timeouts and Camera2 reopen / max-camera-in-use errors. | `20260607_145107-s7-edge-datasaver480p30-rerun/manual-after-failure/logs.json`, `20260607_145107-s7-edge-datasaver480p30-rerun/manual-after-failure/logcat-tail.txt` |

## Conclusions

- iPhone 12 Pro is no longer blocked for debug automation capture on the 0.5x
  lens path. Both squash-relevant `sport1080p60` and 4K `detail4k30` targets
  pass functionally on iOS 26.5.
- iOS saved-video metadata extraction still returns unavailable, so actual
  width/fps proof is not yet available from the native helper.
- The newly connected API 31 S10e passes the baseline 1080p30 target and logs
  actual width/height as `1920x1080`; fps remains unknown.
- S7 and S9-class Samsung devices remain blocked before photo save. This is not
  a UI/settings persistence problem: settings are applied, camera `0` is
  selected, and initialization completes before CameraX/Exynos capture fails.
