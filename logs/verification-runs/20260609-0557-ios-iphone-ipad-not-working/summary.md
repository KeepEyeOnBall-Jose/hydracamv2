# Evidence Run: Diagnose current iPhone and iPad physical app failure

- Source: user-report-2026-06-09
- Slug: `ios-iphone-ipad-not-working`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [x] Connected iPhone/iPad launch state is classified as app pass, bridge failure, signing/trust failure, locked-device failure, or tooling failure
- [x] A run-specific evidence pack records current commands and blockers

## Device Matrix

- iPhone 12 Pro / iOS 26.5, Flutter target
  `00008101-000A68811E43001E`, CoreDevice
  `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`: current
  `com.keepeyeonball` launch and bridge diagnosis.
- iPad (6th generation) / iOS 17.7.11, Flutter target
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, CoreDevice
  `0A947DBD-A462-5BAA-AB84-17F143D41619`: current
  `com.keepeyeonball` launch and bridge diagnosis.

## Evidence

- `flutter devices --device-timeout 10`, `xcrun devicectl list devices`,
  and `xcrun xctrace list devices` all saw both physical iOS devices.
- iPhone `com.keepeyeonball` is installed and launches through
  `devicectl`; `/healthz` passed at `192.168.178.168:4762` with
  `automationTargetId=00008101-000A68811E43001E`.
- iPhone also has the older `com.vectorblanco.hydracam.dev` bundle installed
  with the same visible app name `HydraCam`, which can make Home Screen testing
  ambiguous until the stale bundle is removed or renamed in a future install.
- iPhone screenshot evidence copied from the `com.keepeyeonball` app container:
  `screenshots/iphone-current-not-working.png`.
- iPad lock state is not the blocker: `passcodeRequired=false` and
  `unlockedSinceBoot=true`.
- iPad `devicectl` app-list/process/launch calls fail or time out at the
  CoreDevice streaming/app-control boundary. `xctrace` can launch and record
  the app, proving the installed app reaches Dart.
- Fresh iPad trace
  `device-logs/ipad-app-documents/logs/hydracam-trace-2026-06-09T06-04-56-245815.ndjson`
  shows the root startup failure:
  `SocketException: Failed to create server socket ... address = 0.0.0.0, port = 4762`.
- Identity-filtered bridge scan found only the iPhone bridge on
  `192.168.178.0/24` and no iPad bridge on `169.254.193.0/24`.
- Code change in this run makes automation bridge bind failures non-fatal so a
  stale automation port cannot kill app startup before UI.
- Patched `com.keepeyeonball` Profile build for port `4762` installed on both
  iPhone and iPad. iPhone old `com.vectorblanco.hydracam.dev` bundle was
  removed successfully.
- iPad old `com.vectorblanco.hydracam.dev` uninstall timed out through
  CoreDevice. Patched iPad `4762` launch succeeded, but copied traces still
  showed non-fatal `port = 4762` address-in-use and no reachable bridge.
- Patched iPad alternate-port build (`HYDRACAM_AUTOMATION_PORT=4763`) installed.
  `devicectl` launch timed out, but `xctrace` reached Dart and the trace
  `device-logs/ipad-app-documents-after-xctrace-4763/logs/hydracam-trace-2026-06-09T06-23-37-593483.ndjson`
  shows `Automation bridge listening on port 4763`.
- Even with the iPad bridge listening on `4763`, identity scans found no iPad
  bridge on `192.168.178.0/24` or `169.254.193.0/24`, and direct probes to
  `192.168.178.104`, `169.254.193.202`, and the CoreDevice tunnel address did
  not reach it. Current iPad blocker is network/app-control reachability, not
  Dart bridge startup.
- No physical iOS screen recording was captured in this run; the pack includes
  a blocker note under `video/`.

## Result

- Final disposition: partial. iPhone current `com.keepeyeonball` automation
  launch is alive and screenshot-proven, and the old duplicate dev bundle was
  removed from the iPhone. iPad patched builds install, and the alternate-port
  trace proves the app can start the automation bridge on `4763`, but the bridge
  is not reachable from the Mac and CoreDevice app-control remains flaky. The
  next iPad recovery step needs device-side action: reboot the iPad from the
  device UI if the shell reboot keeps timing out, remove the old
  `com.vectorblanco.hydracam.dev` HydraCam app if it is still visible, accept
  any Local Network/camera/microphone prompts, then rerun the selected iPad
  bridge probe.
