# Evidence Run: Inventory and enable all attached HydraCam devices

- Source: user-request-2026-07-08-all-device-control
- Slug: `all-device-connectivity-inventory`
- Verification tier: C (multi-device-emulated-cluster)
- Status: blocked

## Acceptance Checks

- [ ] Every named target is either reachable by Flutter/ADB/CoreDevice or has a specific operator action recorded
- [ ] Android phones are inventoried by serial, model, Android API, and authorization state
- [ ] iPhone and iPad are inventoried by CoreDevice and Flutter target IDs

## Device Matrix

Current MBA13 inventory:

| Required device | Current identifier | Current state | Operator action |
| --- | --- | --- | --- |
| S7 | `9885e6503930304946` | Controlled by ADB/Flutter as `SM_G935F`, Android 8.0/API 26 | Keep connected and awake. |
| S9 | `29d816ac550b7ece` | Controlled by ADB/Flutter as `SM_G960F`, Android 10/API 29 | Keep connected and awake. |
| S10e | `RF8M90QE7LX` | Controlled by ADB/Flutter as `SM_G970F`, Android 12/API 31 | Keep connected and awake. |
| S10e candidate | `RF8M2125DAJ` | Controlled by ADB as `SM_G970F`, Android 12/API 31; stayed present through a one-minute ADB poll after reconnect | Keep connected and awake. |
| S10e candidate | `RF8M40MT6AW` | Controlled by ADB/Flutter as `SM_G970F`, Android 12/API 31 | Keep connected and awake. |
| iPhone 12 Pro | `00008101-000A68811E43001E` / `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A` | CoreDevice/Flutter reachable, wired, Developer Mode enabled | Keep unlocked for launch/capture. |
| iPad (5) | `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` / `0A947DBD-A462-5BAA-AB84-17F143D41619` | CoreDevice/Flutter reachable, wired, Developer Mode enabled, tunnel connected, unlocked since boot | Keep unlocked for launch/capture. |
| POCO X4 5G | `575ecf2cbd24` | Controlled by ADB/Flutter as `2201116PG`, Android 13/API 33 | Keep connected and awake. |

Extra visible device: iPhone 11 `00008030-000D05302190402E` / `7931E735-717E-5B88-A283-11343FEB0795`; CoreDevice sees it wired and paired, but Developer Mode is disabled. CoreDevice advertises `View Device Screen`, but `devicectl` has no command to enable Developer Mode, the screen URL is not bound to an app on MBA13, and AVFoundation/QuickTime CLI currently sees only the Mac FaceTime camera.

## Evidence

- `commands.log` records MBA13 `adb devices -l`, `flutter devices --device-timeout 10`, `xcrun devicectl list devices`, and USB `ioreg` probes.
- The latest ADB poll showed six controlled Android devices: `29d816ac550b7ece`, `575ecf2cbd24`, `9885e6503930304946`, `RF8M2125DAJ`, `RF8M40MT6AW`, and `RF8M90QE7LX`.
- The latest iPad CoreDevice checks showed a wired tunnel, Developer Mode enabled, `passcodeRequired: false`, and `unlockedSinceBoot: true`.
- Screenshots were captured from controlled Android devices including S7, S9, POCO X4 5G, and the visible S10e targets.

## Result

- Final disposition: original requested fleet is controlled at the host inventory layer. Remaining before full test sessions: install/launch HydraCam on the full set, confirm same-LAN readiness, then run small photo/clip upload/delete flows. Extra iPhone 11 remains a separate broken-screen Developer Mode blocker.
