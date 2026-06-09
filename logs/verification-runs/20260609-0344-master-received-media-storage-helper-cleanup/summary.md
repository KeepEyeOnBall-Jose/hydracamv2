# Evidence Run: Master received-media storage helper cleanup

- Source: cleanup scan: MasterServer._saveMediaLocally storage-manager TODO
- Slug: `master-received-media-storage-helper-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] SessionMediaStorage owns session-directory creation, received-media filename generation, byte writes, and gallery persistence dispatch
- [ ] MasterServer delegates received media saving to the storage helper without changing photo/video session registration
- [ ] Focused storage/server tests, analyzer, diff check, and full Flutter tests pass

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
