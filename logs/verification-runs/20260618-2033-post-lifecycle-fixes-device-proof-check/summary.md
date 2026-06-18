# Evidence Run: Post-iteration hardware UI proof

- Source: docs/control/regular-evaluation-plan.md
- Slug: `post-lifecycle-fixes-device-proof-check`
- Verification tier: D (integration-unit-tests)
- Status: blocked

## Acceptance Checks

- [x] Inventory connected hardware and prove whether current UI lifecycle fixes can be smoke-tested on responsive device automation bridges.

## Device Matrix

- Android: none reported by `adb devices -l`.
- iPhone 12 Pro: unavailable in CoreDevice.
- iPad (5): visible wirelessly and paired, but no automation bridge was reachable.

## Evidence

- `commands.log` records Android, Flutter, CoreDevice, bridge discovery, and
  bounded iPad launch checks.
- `device-logs/ipad-ios-launch-bridge-check/flutter-run.log` shows the iPad
  launch attempt reached Flutter launching but did not expose a bridge.

## Result

- Final disposition: blocked. Device-facing UI proof could not run because no
  screenshot-capable automation bridge was available.
