# Evidence Run: Infer Android Wi-Fi preflight subnet from host route

- Source: AGENTS.md#validation-policy
- Slug: `android-wifi-preflight-auto-subnet`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Unit tests prove route-interface parsing, hex/dotted netmask subnet
  parsing, literal subnet preservation, and the preflight CLI documents
  `--expected-subnet auto` with `--expected-host`.

## Device Matrix

- macOS host, macOS 26.4.1, `macos`, local tooling test host.
- No Android device preflight was run; this pack validates parser/CLI behavior
  only.

## Evidence

- `commands.log` records:
  - `python3 scripts/test_android_wifi_preflight.py`
  - `python3 scripts/android_wifi_preflight.py --help`
  - `python3 -m py_compile scripts/android_wifi_preflight.py scripts/test_android_wifi_preflight.py`

## Result

- Final disposition: passed for static/tooling validation. Run the script
  against attached Android devices before using this as hardware LAN readiness
  proof.
