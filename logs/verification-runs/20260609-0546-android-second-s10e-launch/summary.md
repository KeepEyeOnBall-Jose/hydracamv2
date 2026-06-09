# Evidence Run: Launch HydraCam on second S10e after USB hub recovery

- Source: user follow-up 2026-06-09
- Slug: `android-second-s10e-launch`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] ADB enumerates RF8M90QE7LX as a connected Android device
- [x] HydraCam installs or existing install is preserved on RF8M90QE7LX
- [x] HydraCam launches visibly on RF8M90QE7LX with screenshot or documented blocker

## Device Matrix

- `RF8M90QE7LX` - SM G970F, Android 12 / API 31, single app instance.

## Evidence

- `adb devices -l` enumerated `RF8M90QE7LX` as `model:SM_G970F device:beyond0`.
- `adb -s RF8M90QE7LX install -r build/app/outputs/flutter-apk/app-debug.apk` passed.
- Camera, microphone, fine-location, and coarse-location permissions were granted.
- `adb -s RF8M90QE7LX shell am start -W -n com.amaia23.hydracam/.MainActivity` returned exit code 0.
- `adb -s RF8M90QE7LX shell pidof com.amaia23.hydracam` returned a running process.
- Screenshots:
  - `screenshots/RF8M90QE7LX-launch.png` shows the notification shade over the app.
  - `screenshots/RF8M90QE7LX-hydracam-launch-clean.png` shows the HydraCam slave screen.
- Video: `video/RF8M90QE7LX-launch.mp4`.
- Logcat: `device-logs/RF8M90QE7LX-logcat.txt`.
- Visual note: the launched slave screen is visible but shows `BOTTOM OVERFLOWED BY 92 PIXELS`.

## Result

- Final disposition: passed for `RF8M90QE7LX`. The second S10e was recognized, installed, launched, and visually proved.
