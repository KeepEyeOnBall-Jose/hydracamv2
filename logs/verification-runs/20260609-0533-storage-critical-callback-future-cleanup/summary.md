# Evidence Run: storage critical callback future cleanup

- Source: lib/services/storage_service.dart critical storage callback contract
- Slug: `storage-critical-callback-future-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] StorageService treats the critical-storage callback as FutureOr<void>, invokes it fire-and-forget with error logging, and critical callback failures do not escape storage-level handling.

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
