# Evidence Run: Physical iPhone resumed setup proof recovery

- Source: docs/control/status-and-roadmap.md#camera-setup-and-leveling
- Slug: `physical-iphone-resumed-recovery`
- Verification tier: A (real-hardware)
- Status: blocked

## Acceptance Checks

- [x] Physical iPhone becomes reachable through Flutter, CoreDevice, xctrace, or identity-matched HydraCam automation bridge
- [x] If still unreachable, current recovery probes are recorded with commands and blocker evidence

## Device Matrix

- Jose Ramon’s iPhone, iOS 26.5, iPhone 12 Pro. CoreDevice UUID
  `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`; iOS UDID
  `00008101-000A68811E43001E`. Role: physical iPhone setup-preview proof
  recovery target.

## Evidence

- `commands.log` records baseline unavailable state, scoped
  CoreDeviceService/remotepairingd restarts, device discovery, pairing, launch,
  build, install, bridge discovery, and final network probes.
- The first scoped service restart recovered CoreDevice from `unavailable` to
  `available (paired)` and Flutter listed the iPhone wirelessly as
  `00008101-000A68811E43001E`.
- A setup-role `devicectl` launch succeeded and the old bridge responded at
  `http://192.168.178.168:4762/healthz`, but that installed app was stale:
  it exposed capture/master commands and `set_role`, not the current
  `capture_screenshot` automation command.
- `flutter build ios --profile --dart-define=HYDRACAM_AUTOMATION=true
  --dart-define=HYDRACAM_AUTOMATION_PORT=4762 -t lib/main.dart` passed and
  built `build/ios/iphoneos/Runner.app`.
- Current Profile install attempts through `devicectl device install app`
  failed after the iPhone returned to CoreDevice `unavailable`. Both UDID and
  CoreDevice UUID selectors produced CoreDevice error 1011 with
  `DeviceIdentifier = ecid_2929653534883870`.
- A later unfiltered bridge discovery found `http://192.168.178.153:4762`,
  but logs identified it as an Android setup-preview bridge
  (`/data/user/0/com.amaia23.hydracam/...`), so it was not used as iPhone
  evidence.
- `screenshots/physical-iphone-setup-screenshot-blocked.txt` and
  `video/physical-iphone-setup-video-blocked.txt` document why visual iPhone
  setup evidence could not be captured in this run.

## Result

- Final disposition: blocked. The iPhone recovery path briefly proved wireless
  CoreDevice reachability and app launch, but the device did not remain
  reachable long enough to install and relaunch the current automation build
  for screenshot proof. The remaining action is device-side: keep the physical
  iPhone unlocked/on the same LAN, refresh its wireless developer pairing if
  needed, then rerun install plus setup-role launch.
