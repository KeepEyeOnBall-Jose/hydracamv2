# Evidence Run: Repair blank stored session GUID restore

- Source: docs/control/backlog-import.md#historical-javi-immediate-backlog-row-35
- Slug: `blank-stored-session-guid-restore`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Stored metadata with a blank sessionGuid restores through the storage identifier when the storage identifier is a service GUID
- [x] Preferred session identifiers trim GUIDs and fall back to legacy IDs for blank GUID values

## Device Matrix

- Tier D service/model validation only; no device under test was required.

## Evidence

- `commands.log` records baseline focused model/session tests passing before
  adding the new regressions.
- Red coverage reproduced `CaptureSession.preferredIdentifier` returning a
  whitespace GUID instead of the legacy ID.
- Red coverage reproduced `restoreSessionFromMetadata()` rejecting blank stored
  GUID metadata with `Stored media    is not attached to a service session`.
- After the fix, both focused regressions, the focused
  session/model/details/previous-session/gallery-candidate set, focused
  analyzer, full analyzer, and full Flutter test suite passed.

## Result

- Final disposition: passed. Stored metadata with blank or whitespace-only
  `sessionGuid` is repaired from the storage identifier during metadata load,
  and preferred identifiers now trim GUIDs before falling back.
