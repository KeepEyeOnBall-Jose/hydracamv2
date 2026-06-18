# Evidence Run: Log critical storage trigger and align resource warnings

- Source: docs/control/backlog-import.md#5-add-critical-battery-autostop
- Slug: `resource-warning-diagnostics`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] StorageService focused coverage proves the critical storage forced-stop
  trigger logs the available GB value, analyzer passes, and the full Flutter
  test suite remains green after shared warning-surface theme updates.

## Device Matrix

- macOS host, macOS 26.4.1, `macos`, local Flutter test host.
- No platform battery/storage event was fired; this is static/service/widget
  validation.

## Evidence

- `commands.log` records:
  - `flutter test --no-pub test/services/storage_service_test.dart`
  - `flutter analyze --no-pub`
  - `flutter test --no-pub`

## Result

- Final disposition: passed for local/static/Tier D validation. Real-device or
  emulator platform battery/storage event proof remains open.
