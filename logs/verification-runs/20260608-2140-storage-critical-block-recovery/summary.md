# Evidence Run: T-017: Critical storage block recovery

- Source: docs/control/backlog-import.md
- Slug: `storage-critical-block-recovery`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] StorageService clears recording block when available storage recovers above the critical threshold, while still allowing low-storage warning behavior below the low threshold.

## Device Matrix

- StorageService widget test runner, macOS host / Flutter test, role
  `storage-recovery`, identifier `StorageService critical block recovery`.

## Evidence

- `commands.log`: captured RED failure where `isRecordingBlocked` stayed true
  after storage recovered above the critical threshold, then GREEN focused
  storage service test run.
- `device-logs/storage-recovery-test-commands.log`: copy of the test command
  log for the evidence pack device-log requirement.
- `screenshots/storage_critical_block_recovery.png`: rendered proof of the
  T-017 storage recovery behavior.
- `video/storage_critical_block_recovery_proof.mp4`: 4.5-second proof video for
  the same RED / CHANGE / GREEN flow.

## Result

- Final disposition: passed for the bounded T-017 local slice. Real-device
  storage-pressure recording proof remains the production closure gate.
