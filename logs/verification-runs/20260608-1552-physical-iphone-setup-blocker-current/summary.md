# Evidence Run: Physical iPhone camera setup proof retry

- Source: docs/control/status-and-roadmap.md#camera-setup-and-leveling
- Slug: `physical-iphone-setup-blocker-current`
- Verification tier: A (real-hardware)
- Status: blocked

## Acceptance Checks

- [ ] Physical iPhone appears in Flutter/CoreDevice or an identity-matched automation bridge is reachable
- [x] If unreachable, blocker evidence records Flutter, CoreDevice, xctrace, and bridge-host probes

## Device Matrix

- Physical iPhone 12 Pro / iOS 26.5 /
  CoreDevice identifier `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A` /
  xctrace identifier `00008101-000A68811E43001E` /
  physical iPhone setup proof blocker retry.

## Evidence

- `flutter devices --device-timeout 10` still does not list the physical iPhone
  as a connected target and reports local-network browsing error code `-27`.
- `xcrun devicectl list devices` lists Jose Ramon’s iPhone as `unavailable`.
- `xcrun xctrace list devices` lists Jose Ramon’s iPhone under
  `Devices Offline`.
- `xcrun devicectl device info lockState --device
  AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A` fails because CoreDevice cannot locate
  the device identifier.
- The last known iPhone bridge from
  `logs/verification-runs/latest-rotating-master-slave-warm-summary.json`,
  `http://192.168.178.168:4762/healthz`, times out.
- `python3 scripts/ios_capture_repro.py --host auto --scan-subnet
  192.168.178.0/24 --device-id 00008101-000A68811E43001E --timeout 20` failed
  with `Automation bridge was not discovered on 192.168.178.0/24 port 4762`.
- Because the device is not reachable, this pack records explicit blocked
  placeholder artifacts:
  `screenshots/physical-iphone-screenshot-blocked.txt`,
  `video/physical-iphone-video-blocked.txt`, and
  `device-logs/physical-iphone-current-blocker.txt`.

## Result

- Final disposition: blocked.
- This is an external device availability blocker. The physical iPhone cannot
  currently be reached through Flutter/CoreDevice/xctrace and has no reachable
  identity-matched HydraCam automation bridge on the current LAN.
- The active all-device objective still lacks the physical iPhone setup
  screenshot/proof. The repo cannot produce that artifact until the iPhone is
  unlocked/online/paired or its installed automation bridge becomes reachable.
