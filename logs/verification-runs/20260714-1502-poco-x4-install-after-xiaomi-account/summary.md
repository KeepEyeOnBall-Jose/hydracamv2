# Evidence Run: Re-admit POCO X4 Pro 5G to current-build Android deployment

- Source: docs/control/status-and-roadmap.md#current-mobile-status
- Slug: `poco-x4-install-after-xiaomi-account`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] POCO 2201116PG is visible to ADB as an authorized device
- [x] Current signed HydraCam APK installs successfully
- [x] HydraCam launches and its installed package/version is recorded

## Device Matrix

| Device | Identifier | OS | Intended proof | Current state |
| --- | --- | --- | --- | --- |
| POCO X4 Pro 5G / `2201116PG` | `575ecf2cbd24` | Android 13 / API 33 | Install and launch current HydraCam build | Passed with debug automation build `1.4.0+19`; process PID `5892`. |

## Evidence

- `commands.log` records the initial local ADB inventory without the POCO and
  the first MBA13 SSH timeout, followed by the resumed local inventory with
  authorized POCO serial `575ecf2cbd24`.
- Current checkout `8f1892d51805aed1c99138cbac58b77ff511bb11` built
  `build/app/outputs/flutter-apk/app-debug.apk` with
  `HYDRACAM_AUTOMATION=true`. APK SHA-256 is
  `d3f34ecc7b5bd33e86b33d0f74487f95d55a976d66a065eefed045881bc5fe76`;
  archive verification passed and signer SHA-256 is
  `091de46955d0d168dd3b2091b8aaa89d7f99fba405e008ceec7de5ee17a3c9c1`.
- The first recorded install attempt reproduced
  `INSTALL_FAILED_USER_RESTRICTED` because MIUI's ten-second confirmation was
  not selected. `screenshots/poco-live-install-prompt.png` records the exact
  HydraCam confirmation dialog.
- The next attempt selected `Auswahl merken` and `Installieren` at the device's
  native 1080x2180 coordinates. A subsequent recorded `adb install -r` passed
  unattended with `Success`, proving MIUI retained the decision.
- `commands.log` records successful `MainActivity` launch, PID `5892`, package
  `com.amaia23.hydracam`, `versionName=1.4.0`, `versionCode=19`, minSdk 24,
  targetSdk 35, first install at `2026-07-14 15:11:47`, and update at
  `2026-07-14 15:12:16`.
- `screenshots/poco-hydracam-launched.png` shows the real device on HydraCam
  Master Control with hardware `2201116PG` and app `1.4.0+19`.
- `video/poco-hydracam-launched.mp4` is an 8.69-second H.264 screen recording;
  the device fell back from unsupported 1080x2400 screen recording to
  720x1280.
- `device-logs/poco-hydracam-launch-logcat.txt` shows the app selecting master
  mode and starting its WebSocket server on port 4040, with no matched Flutter
  exception, fatal exception, ANR, or overflow marker.
- `screenshots/unavailable.txt`, `video/unavailable.txt`, and
  `device-logs/unavailable.txt` preserve the initial reachability-blocked phase
  that was superseded when the user connected the POCO locally.

## Result

- Final disposition: passed for current-build installation, unattended update,
  launch, process, package, screenshot, video, and startup-log proof.
- The former Xiaomi account/SIM policy blocker is cleared. POCO
  `575ecf2cbd24` is now a usable ADB deployment target on this Mac.
- Scope boundary: this run did not claim camera capture, upload, or multi-device
  session proof. The launched UI reports Wi-Fi `JuJo` at `192.168.0.9`, while
  the five-phone lab fleet was last proven on `Astral Express` at
  `192.168.178.0/24`; align the POCO's LAN before adding it to a shared session.
