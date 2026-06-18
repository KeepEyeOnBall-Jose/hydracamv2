# Evidence Run: Remove local-session runtime split and add debug session cleanup contract

- Source: docs/superpowers/plans/2026-06-18-session-upload-state-debug-cleanup.md
- Slug: `session-upload-state-debug-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] No runtime automation path exposes local-only sessions
- [x] Flutter analyzer passes
- [x] Focused session/upload/debug cleanup tests pass
- [x] Full Flutter test suite passes

## Device Matrix

- macOS host, macOS 26.4.1, `macos`, local test host.
- iPad (5) wireless, iOS 17.7.11,
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, visible but not launched in this
  Tier D rerun.
- Jose Ramon iPhone wireless, iOS 26.5,
  `00008101-000A68811E43001E`, visible but not launched in this Tier D rerun.

## Evidence

- `commands.log` records:
  - `python3 scripts/test_no_local_sessions.py`
  - `flutter analyze --no-pub`
  - focused session/upload/debug cleanup `flutter test --no-pub ...`
  - full `flutter test --no-pub`
  - `adb devices -l`
  - `flutter devices --device-timeout 10`
- Same-day Android setup-route UI smoke for this working tree is available in
  `logs/verification-runs/20260618-0953-session-concepts-android-ui/`.

## Result

- Final disposition: passed for local/static/Tier D validation. ADB reported no
  attached Android devices. Flutter saw wireless iPad/iPhone, but physical iOS
  launch was not rerun because this session exposes only simulator Xcode MCP
  capabilities and the repo marks no-tooling debug iOS launch as unreliable.
  Live debug-build capture/upload deletion proof remains an open validation
  follow-up.
