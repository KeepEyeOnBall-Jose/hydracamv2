# Evidence Run: Run HydraCam on all four ADB-visible Android devices

- Source: user request 2026-06-09
- Slug: `android-four-adb-launch-smoke`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [ ] ADB and Flutter both enumerate the four intended Android serials
- [ ] HydraCam is installed or an existing install is preserved and launched on each Android serial
- [x] Each Android serial has a visible launched app screen or a documented launch blocker with log evidence

## Device Matrix

- `29d816ac550b7ece` - SM G960F, Android 10 / API 29, single app instance.
- `9885e6503930304946` - SM G935F, Android 8.0 / API 26, single app instance.
- `RF8M21J8XRT` - SM G970F, Android 12 / API 31, expected from earlier ADB inventory but absent during launch/install.
- `RF8M90QE7LX` - SM G970F, Android 12 / API 31, expected from earlier ADB inventory but absent during launch/install.
- `575ecf2cbd24` - 2201116PG, Android 13 / API 33, appeared in the refreshed ADB inventory during the run.

## Evidence

- `flutter build apk --debug` passed and produced `build/app/outputs/flutter-apk/app-debug.apk`.
- `29d816ac550b7ece` accepted `adb install -r`, permissions were granted, `am start -W` returned exit code 0, `pidof com.amaia23.hydracam` returned PID `15955`, and screenshots/video/logcat were captured.
- `9885e6503930304946` accepted `adb install -r`, permissions were granted, `am start -W` returned exit code 0, `pidof com.amaia23.hydracam` returned PID `8880`, and screenshots/video/logcat were captured.
- `RF8M21J8XRT` and `RF8M90QE7LX` were no longer visible to ADB when install was attempted; both failed with `adb: device '<serial>' not found`.
- Restarting the ADB server did not restore the missing S10e serials. Final `adb devices -l` listed only `29d816ac550b7ece`, `575ecf2cbd24`, and `9885e6503930304946`.
- `575ecf2cbd24` rejected install with `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`, and `pm path com.amaia23.hydracam` returned exit code 1, so there was no existing HydraCam install to launch.
- Screenshots:
  - `screenshots/29d816ac550b7ece-launch-clean.png`
  - `screenshots/9885e6503930304946-launch.png`
- Videos:
  - `video/29d816ac550b7ece-launch.mp4`
  - `video/9885e6503930304946-launch.mp4`
- Device logs:
  - `device-logs/29d816ac550b7ece-logcat.txt`
  - `device-logs/9885e6503930304946-logcat.txt`

## Result

- Final disposition: partial. HydraCam was built, installed, launched, and visually proved on two Android devices. The all-four request is blocked by current ADB/device state: the two S10e serials from the earlier inventory disappeared, and the newly visible Xiaomi/Redmi device blocks ADB installs and has no existing HydraCam package.
