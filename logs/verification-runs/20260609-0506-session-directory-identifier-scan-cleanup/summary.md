# Evidence Run: JAVI IMMEDIATE BACKLOG row 35

- Source: docs/control/backlog-import.md row 35
- Slug: `session-directory-identifier-scan-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] SessionManager uses one session-directory identifier extraction path so scan/reconstruct preserves the full identifier after the session_ prefix, including identifiers containing underscores

## Device Matrix

- Dart/Flutter service test surface on macOS host runtime.
- Temp application-documents directory with `session_scan_preserve_full_guid`.
- No physical device required for this Tier D session-manager cleanup.

## Evidence

- `commands/flutter-test-test-services-session-manager-test-dart/command.txt`
  captures `flutter test test/services/session_manager_test.dart`.
- `commands/flutter-test-test-services-session-manager-test-dart/stdout.txt`
  records `+19: All tests passed!`.
- The regression first reproduced truncation to `guid` when reconstruction used
  `split("_").last`, then passed after reconstruction reused the same
  `session_` prefix-strip helper as the available-session listing path.

## Result

- Final disposition: local service proof passed for preserving full
  previous-session directory identifiers. Row 35 remains open for real
  old-media attachment smoke evidence and any remaining controller/view GUID
  audit outside this service path.
