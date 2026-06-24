# Evidence Run: Validate eight-target rotating master/slave role-switch proof

- Source: docs/control/status-and-roadmap.md#multi-device-capture
- Slug: `eight-target-random-master-role-switch`
- Verification tier: C (multi-device-emulated-cluster)
- Status: blocked

## Acceptance Checks

- [ ] Eight non-web HydraCam targets are visible: five physical devices, one iOS simulator, one Android emulator, and macOS
- [ ] One randomly selected capture-capable target becomes master
- [ ] The promoted master exposes automation commands and sees every other selected target as a connected client

## Device Matrix

- `RF8M90QE7LX` - physical Samsung S10e / Android 12. Original random master.
- `9885e6503930304946` - physical Samsung S7 edge / Android 8.
- `RF8M21J8XRT` - physical Samsung S10e / Android 12. Fallback LAN-capable random master.
- `emulator-5554` - Android emulator / API 34. Fallback emulator random master.
- `00008101-000A68811E43001E` - physical iPhone / iOS 26.5.
- `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` - physical iPad / iOS 17.7.11.
- `5CF4A12E-A8B5-4285-AE86-407B9067CB5F` - iPhone 16 Plus simulator / iOS 18.4.
- `macos` - native macOS debug build.

## Evidence

- Dry run selected all eight non-web HydraCam targets and original random master `RF8M90QE7LX`.
- `device-logs/eight-target-random-master-after-adb-timeouts/` shows `RF8M90QE7LX` timing out on `pm grant`, `am force-stop`, and `am start`.
- `device-logs/seven-target-fallback-master-emulator-immediate-forwarded/` shows every reachable bridge accepted `set_role`, but emulator master saw no connected clients.
- `device-logs/seven-target-fallback-master-rf8m21-immediate/` shows every reachable bridge accepted `set_role`; physical Android master `RF8M21J8XRT` saw three connected clients on `192.168.0.0/24`, but not the complete selected set.
- Pack validation still requires screenshot/video files for a complete Tier C evidence pack.

## Result

- Final disposition: blocked.
- Primary blocker: original random master `RF8M90QE7LX` is visible in ADB inventory but Android package/activity-manager commands time out, preventing the automation bridge from warming.
- Secondary blocker: the currently selected devices are split across routable networks/subnets, and the Android emulator is not a LAN-routable master for physical clients.
