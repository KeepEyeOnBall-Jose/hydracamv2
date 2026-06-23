# Physical S10e Slave Landscape Proof

- Status: passed on physical Samsung S10e `RF8M21J8XRT`.
- Device: `SM_G970F`, Android 12, ADB serial `RF8M21J8XRT`.
- Flow: launched the current automation-enabled APK into standby, forced device landscape, switched runtime role to the real `SlaveScreen` through `/commands/set_role`, captured an in-app screenshot through `/commands/capture_screenshot`, collected bridge logs, logcat, window focus, and display-size evidence, then restored rotation settings.
- Screenshot: `screenshots/RF8M21J8XRT-slave-landscape.png`.
- Screenshot viewport: `674 x 360`, `91370` bytes.
- Device logs: `device-logs/RF8M21J8XRT/slave-landscape-logcat.txt` and `device-logs/RF8M21J8XRT/bridge-logs.json`.
- Window focus: `com.amaia23.hydracam/.MainActivity` was focused during the capture.
- Visual check: the compact landscape slave UI rendered with the status panel,
  camera preview, disabled add-media control, and media list visible without
  overlap.
- Overflow scan: no `RenderFlex overflowed` / `overflowed by` markers found in the captured evidence.
- Notes: companion S10e `RF8M90QE7LX` was ADB-visible and installed/running, but its automation `capture_screenshot` call timed out in both the broader setup/standby run and the narrowed standby-only rerun. Its blocker is recorded in `../20260623-0330-s10e-physical-standby-proof/summary.md`.
