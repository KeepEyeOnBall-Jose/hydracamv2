# Evidence Run: macOS dev-host automation define cleanup

- Source: scripts/deploy_macos_dev_host.zsh debug probe stale automation dart-define names
- Slug: `macos-dev-host-automation-define-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] macOS dev-host debug probe uses the same HYDRACAM_AUTOMATION and HYDRACAM_AUTOMATION_ROLE dart defines read by lib/automation/automation_config.dart, and script contract tests reject the stale legacy define names

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
