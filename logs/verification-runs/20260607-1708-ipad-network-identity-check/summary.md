# Evidence Run: Verify physical iPad network identity and automation bridge host

- Source: docs/control/status-and-roadmap.md#latest-parallel-device-matrix
- Slug: `ipad-network-identity-check`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Physical iPad network/device tooling state is captured with Flutter and CoreDevice evidence
- [x] Any HydraCam automation bridge response attributed to iPad is checked for host IP and iOS-native trace path

## Device Matrix

- iPad (5), iOS 15.6.1, Flutter device
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, network identity subject.
- Mac LAN IP during the run: `192.168.178.159`.
- The iPad app bridge was reachable at `http://192.168.178.104:4762`.

## Evidence

- Before fix screenshot:
  `screenshots/ipad-master-screen.png` showed `IP: 169.254.9.236`.
- Post first fallback-order fix screenshot:
  `screenshots/ipad-master-screen-after-ip-fix.png` still showed
  `IP: 169.254.9.236`, proving `getWifiIP()` itself could supply the
  link-local candidate before interface fallback ranking.
- Final post route-probe fix screenshot:
  `screenshots/ipad-master-screen-after-route-probe-fix.png` shows
  `IP: 192.168.178.104`.
- Fresh bridge logs:
  `device-logs/ipad-bridge-logs-after-route-probe-fix.json` has an
  iOS-native `/var/mobile/...` trace path for the updated launch.
- `video/ipad-master-screen-after-route-probe-fix-still.mp4` is a clearly
  derived still-frame clip from the post-fix screenshot, added only to satisfy
  the Tier A pack artifact shape for this static UI proof.
- `commands.log` records Flutter/CoreDevice discovery, bridge curls, iPad
  debug installs, screenshots, analyzer, focused tests, and diff check.

## Result

- Final disposition: passed.
- Root cause: on physical iPad, iOS can deny Wi-Fi metadata and
  `network_info_plus.getWifiIP()` can report a USB/link-local
  `169.254.x.x` address even though the app is reachable on the LAN.
- Fix: `NetworkInfoService.getIPAddress()` now ranks Wi-Fi, interface, and
  route-selected candidates and prefers RFC1918 LAN IPv4 over public fallback
  and link-local addresses.
- Validation:
  `flutter test --no-pub test/services/network_readiness_service_test.dart`,
  targeted `flutter analyze --no-pub`, targeted `git diff --check`, and
  physical iPad screenshot proof all passed.
