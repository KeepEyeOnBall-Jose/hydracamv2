# Evidence Run: Scope store readiness checks to selected upload lane

- Source: docs/control/status-and-roadmap.md#store-distribution
- Slug: `store-readiness-mode-scope`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] upload-ios preflight does not emit Android-only failures
- [x] upload-android preflight does not emit iOS-only failures
- [x] Real upload-ios/upload-android preflights still run lane-specific gates

## Device Matrix

- Not required for tier D script/fixture coverage.

## Evidence

- Red regression: `python3 scripts/test_store_readiness_mode_scope.py` failed because `upload-ios` emitted Android-only failures and `upload-android` emitted iOS-only failures.
- Green regression: `python3 scripts/test_store_readiness_mode_scope.py` passed after platform static, command, icon, signing, and artifact checks were scoped to the selected lane.
- Syntax: `bash -n scripts/check_store_readiness.sh` passed.
- Compile: `python3 -m py_compile scripts/test_store_readiness_mode_scope.py` passed.
- Live diagnostics: `upload-ios` reported iOS-only blockers and `upload-android` reported Android-only blockers, with exit codes captured in `commands.log`.
- Diff hygiene: `git diff --check` passed.

## Result

- Final disposition: passed. Store readiness upload lane checks now skip opposite-platform gates while preserving lane-specific blockers.
