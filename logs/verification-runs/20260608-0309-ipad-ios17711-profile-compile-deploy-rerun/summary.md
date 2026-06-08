# Evidence Run: iPad iOS 17.7.11 Profile compile and deployment rerun

- Source: user request 2026-06-08: ipad updated; do another run of compile and deployment
- Slug: `ipad-ios17711-profile-compile-deploy-rerun`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Profile iOS build compiles with HydraCam automation enabled
- [x] Fresh iPad install/deploy attempt either reaches the physical iPad or records the current pairing/deployment blocker

## Device Matrix

- iPad (5), iPad7,5 / iOS 17.7.11 21H461,
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, deployment target.

## Evidence

- `commands.log` captures the before/after device inventory, pairing attempt,
  Profile builds, install/warm-prime runner, `/healthz`, and post-install
  visibility checks.
- `device-logs/devicectl-install.json` records successful install of
  `com.vectorblanco.hydracam.dev` to
  `/private/var/containers/Bundle/Application/9ED9D376-FD53-4D09-A77C-5906A4DAF68B/Runner.app/`.
- `device-logs/warm-bridge-confirmed.json` records warm-prime pass with no
  missing iPad bridge.
- `device-logs/bridge-health.json` records the bridge health response:
  `automationTargetId=8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`.
- `screenshots/not-captured.txt` and `video/not-captured.txt` document that
  this deployment lane did not collect visual media.

## Result

- Final disposition: passed. The first warm-prime runner invocation returned
  `ios_warm_bridge_missing`, but the app became reachable immediately after at
  `http://192.168.178.104:4762/healthz`. A follow-up warm-prime confirmation
  passed without relaunching, and post-install `flutter devices`, `xctrace`,
  and CoreDevice all show the iPad online/paired on iOS 17.7.11.
