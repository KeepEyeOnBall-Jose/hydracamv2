# Evidence Run: Launch HydraCam on S10e behind monitor USB hub

- Source: user follow-up 2026-06-09
- Slug: `android-s10e-monitor-hub-launch`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] ADB enumerates RF8M21J8XRT as a connected Android device
- [x] HydraCam installs or existing install is preserved on RF8M21J8XRT
- [x] HydraCam launches visibly on RF8M21J8XRT with screenshot or documented blocker

## Device Matrix

- `RF8M21J8XRT` - SM G970F, Android 12 / API 31, single app instance, connected through the monitor USB hub path.

## Evidence

- `adb devices -l` enumerated `RF8M21J8XRT` as `model:SM_G970F device:beyond0`.
- `adb -s RF8M21J8XRT install -r build/app/outputs/flutter-apk/app-debug.apk` passed.
- Camera, microphone, fine-location, and coarse-location permissions were granted.
- `adb -s RF8M21J8XRT shell am start -W -n com.amaia23.hydracam/.MainActivity` returned exit code 0.
- `adb -s RF8M21J8XRT shell pidof com.amaia23.hydracam` returned a running process.
- Screenshot: `screenshots/RF8M21J8XRT-launch.png`.
- Video: `video/RF8M21J8XRT-launch.mp4`.
- Logcat: `device-logs/RF8M21J8XRT-logcat.txt`.
- Visual note: the launched slave screen is visible but shows `BOTTOM OVERFLOWED BY 92 PIXELS`, matching the overflow class also observed on the G935F launch smoke.

## Result

- Final disposition: passed for `RF8M21J8XRT`. The monitor-hub S10e was recognized, installed, launched, and visually proved.
