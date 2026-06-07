# 2026-06-07 Post-Label Device Matrix

Fresh one-by-one run after changing the video profile selector to show concrete
targets such as `1080p at 30 fps` instead of arbitrary profile names.

## Build And Validation Context

- Current debug APK rebuilt with
  `flutter build apk --debug --dart-define=HYDRACAM_AUTOMATION=true`.
- Focused UI/model tests and `flutter analyze` passed before this matrix.
- The run intentionally records `videoCaptureTarget` from `/settings` where
  available to prove the target text exposed by automation.

## Results

| Device | Target | Result | Evidence |
| --- | --- | --- | --- |
| macOS | `autoBack` + `standard1080p30` | Passed local automation capture. `/settings` reported `videoCaptureTarget: 1080p at 30 fps`. | `macos-autoBack-standard1080p30/summary.json`, `macos-autoBack-standard1080p30/automation-snapshots.json` |
| Samsung S10e `RF8M90QE7LX` | `autoBack` + `standard1080p30` | Passed: one photo, one video, session ended. `/settings` reported `1080p at 30 fps`; metadata logged `1920x1080, unknown fps, 3936 ms`. | `20260607_150307-post-label-rf8m90qe7lx-standard1080p30/summary.json`, `20260607_150307-post-label-rf8m90qe7lx-standard1080p30/RF8M90QE7LX/logs.json` |
| Samsung S10e `RF8M21J8XRT` | `autoBack` + `standard1080p30` | Passed: one photo, one video, session ended. `/settings` reported `1080p at 30 fps`; metadata logged `1920x1080, unknown fps, 3969 ms`. | `20260607_150354-post-label-rf8m21j8xrt-standard1080p30/summary.json`, `20260607_150354-post-label-rf8m21j8xrt-standard1080p30/RF8M21J8XRT/logs.json` |
| Samsung SM-G960F `29d816ac550b7ece` | `autoBack` + `standard1080p30` | Passed on this rerun: one photo, one video, session ended. `/settings` reported `1080p at 30 fps`; metadata logged `1920x1080, unknown fps, 4126 ms`. This supersedes the earlier G960F failure from `20260607-new-devices-rerun/`. | `20260607_150446-post-label-g960f-standard1080p30/summary.json`, `20260607_150446-post-label-g960f-standard1080p30/29d816ac550b7ece/logs.json` |
| Samsung S7 edge `9885e6503930304946` | `autoBack` + `standard1080p30` | Failed before photo save. The app selected camera `0` and initialized, then photo capture timed out after 12 seconds. Logcat still shows ExynosCamera3 wait timeouts and Camera2 reopen / max-camera-in-use errors. | `20260607_150551-post-label-s7-edge-standard1080p30/manual-after-failure/logs.json`, `20260607_150551-post-label-s7-edge-standard1080p30/manual-after-failure/logcat-tail.txt` |
| iPhone 12 Pro / iOS 26.5 | `ultraWide` + `sport1080p60` | Passed: one photo, one video, recording stopped. Bridge `192.168.178.141`, trace path under `/var/mobile/`, selected camera `com.apple.avfoundation.avcapturedevice.built-in_video:5`, `/settings` reported `1080p at 60 fps`. Saved-video metadata unavailable. | `iphone12pro-ultrawide-sport1080p60/summary.json`, `iphone12pro-ultrawide-sport1080p60/automation-snapshots.json` |
| iPad 5 / iOS 15.6.1 | `autoBack` + `standard1080p30` | Passed only in the explicit-host run. Bridge `192.168.178.104`, trace path under `/var/mobile/`, `/settings` reported `1080p at 30 fps`. Saved-video metadata unavailable. | `ipad-autoBack-standard1080p30-explicit-104/summary.json`, `ipad-autoBack-standard1080p30-explicit-104/automation-snapshots.json` |
| iOS simulator / iPhone 16 Plus | `autoBack` + `standard1080p30` | Launch/automation bridge passed, but capture is not valid because the simulator has no cameras. Logs show `No cameras found on device` and `No cameras available on this device`. | `ios-simulator-autoBack-standard1080p30/flutter-run.log` |

## Invalidated Artifacts

- `ipad-autoBack-standard1080p30/` and
  `ipad-autoBack-standard1080p30-clean/` are not accepted as iPad proof because
  auto-discovery attached to the iPhone bridge at `192.168.178.141`. The
  accepted iPad evidence is `ipad-autoBack-standard1080p30-explicit-104/`.

## Current Matrix State

- Current baseline 1080p30 capture passes on macOS, both S10e phones, G960F,
  iPhone 12 Pro, and physical iPad.
- iPhone 12 Pro 0.5x squash target still passes at `1080p at 60 fps`.
- iOS saved-video metadata extraction remains unavailable.
- Samsung S7 edge remains the only connected physical mobile device that fails
  before photo capture.
- iOS simulator remains launch/UI-only because no camera is exposed.
