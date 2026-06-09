# Evidence Run: automation localOnly guard cleanup

- Source: scripts/test_no_local_sessions.py and lib/master/master_screen.dart localOnly split-literal guard
- Slug: `automation-local-only-guard-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Automation start_session keeps backend-only behavior with an explicit legacy localOnly rejection guard, no obfuscated localOnly string concatenation, and capture scripts do not send localOnly or disable uploads

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
