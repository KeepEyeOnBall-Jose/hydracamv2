# Evidence Run: Post-iteration connected-device proof check

- Source: docs/control/regular-evaluation-plan.md#start-every-run
- Slug: `post-iteration-device-proof-check`
- Verification tier: C (multi-device-emulated-cluster)
- Status: partial

## Acceptance Checks

- [x] Inventory connected devices and record whether same-turn hardware proof is available after local UI/service fixes.
- [ ] Complete same-turn hardware UI/capture proof on an attached responsive device.

## Device Matrix

- No Android devices attached (`adb devices -l` returned an empty list).
- iPad (5), iOS 17.7.11, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`:
  Flutter and `devicectl` reported the device available/paired, but no
  identity-matched automation bridge exposing `capture_screenshot` appeared on
  `192.168.178.0/24:4762` after a bounded launch attempt.
- iPhone 12 Pro, id `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`: `devicectl`
  reported unavailable and Flutter LAN browsing failed with code `-27`.

## Evidence

- `adb devices -l`: no Android devices attached.
- `xcrun devicectl list devices`: iPad available/paired; iPhone unavailable.
- `flutter devices --device-timeout 10`: macOS, Chrome, and wireless iPad
  visible; iPhone discovery failed with code `-27`.
- `scripts/discover_automation_bridge.py` found no iPad bridge exposing
  `capture_screenshot`.
- `scripts/ios_capture_repro.py --launch ...` started `flutter run` on the
  iPad but failed because the automation bridge was not discovered on
  `192.168.178.0/24:4762`.

## Result

- Final disposition: partial. Local code/test proof is complete for this
  iteration, but same-turn hardware proof remains blocked until a selected iOS
  automation bridge is warm/launchable or Android hardware is attached.
