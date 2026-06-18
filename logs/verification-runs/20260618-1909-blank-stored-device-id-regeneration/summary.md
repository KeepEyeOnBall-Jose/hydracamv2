# Evidence Run: Regenerate blank stored device IDs

- Source: docs/control/backlog-import.md#network-device-identity
- Slug: `blank-stored-device-id-regeneration`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Blank or whitespace stored device IDs are replaced with a generated UUID
- [x] Existing nonblank stored device IDs are preserved
- [x] Focused device service tests, analyzer, full Flutter suite, and diff hygiene pass

## Device Matrix

- Static Flutter service test lane on local macOS host; no attached device
  required for this local-preference repair.

## Evidence

- Red regression reproduced the bug: a whitespace-only stored `device_id`
  was returned as the device ID.
- Green focused coverage passed for blank stored ID regeneration and preserving
  an existing nonblank ID.
- `flutter test --no-pub test/services/device_service_test.dart` passed.
- `flutter analyze --no-pub` passed.
- `flutter test --no-pub` passed with 472 tests.
- `git diff --check` passed.

## Result

- Final disposition: passed. `DeviceIdService` now treats blank or
  whitespace-only stored device IDs as missing, generates and persists a new
  UUID, and keeps existing nonblank IDs unchanged.
