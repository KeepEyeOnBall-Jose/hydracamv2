# Evidence Run: Audit stored-session GUID and storage-key naming

- Source: docs/control/backlog-import.md#historical-javi-immediate-backlog-row-35
- Slug: `stored-session-guid-storage-key-audit`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Previous-session and gallery candidate code keep metadata GUIDs distinct from local storage directory keys
- [x] Existing restore and candidate-source tests preserve behavior while ambiguous controller/view identifiers are clarified

## Device Matrix

- Tier D service/model and controller naming validation only; no device under
  test was required.

## Evidence

- `commands.log` records the existing focused previous-session, gallery
  candidate-source, and session-manager tests passing before the refactor.
- Added characterization coverage proves `GallerySessionCandidateSource` can
  load metadata from a local storage directory key while preserving the
  metadata `sessionGuid` as the candidate's preferred identifier.
- After the naming cleanup, focused previous-session/candidate/session-manager
  tests, focused analyzer, full analyzer, and full Flutter tests passed.

## Result

- Final disposition: passed. Ambiguous previous-session controller/source local
  names now use `storageIdentifier` when they refer to local folder keys, while
  metadata GUID behavior stays unchanged.
