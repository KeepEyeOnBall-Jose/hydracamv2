# Media Timeline Autonomous Sync Grill Handoff

Status: annotated design input for a separate `grill-with-docs` session in the
Media Timeline repository. This is not an implementation specification.

## Purpose

Define the Media Timeline side of HydraCam's autonomous Sync/Ready lifecycle
without weakening the phone's deletion boundary. The originating field
scenario involved eight phones from one multicamera squash training event:
four phones were ingested, SHA-256 verified, linked to the event, and cleared.
The target product should make that outcome autonomous and durable.

Media Timeline's repository currently has a priority freeze. The future grill
must check its active `AGENTS.md` before treating this handoff as authority to
implement anything.

## Decisions Already Accepted on the HydraCam Side

These are constraints for the Media Timeline grill, not questions to reopen
implicitly:

1. The canonical lifecycle is per Captured Original, not per charging cable
   connection or one monolithic batch.
2. A Sync Item durably tracks one Captured Original through transfer, integrity
   verification, event linkage, and source clearance.
3. Device-facing Sync states are derived from the Sync Items plus current
   operating conditions.
4. `Fully Charged` is a battery qualifier, not proof that Sync is complete.
5. Automatic Clearance is enabled by default.
6. Automatic Clearance requires a Clearance Receipt durably retained on the
   phone before deletion.
7. A Clearance Receipt binds all of:
   - the Captured Original's SHA-256;
   - the Captured Original's byte length;
   - a durable File Registry identity;
   - durable linkage to the intended event;
   - explicit backend acceptance.
8. Transfer completion, HTTP success, or File Registry registration without
   event linkage is insufficient for clearance.
9. Autonomous Sync is initiated by the phone through the authenticated Media
   Timeline bridge; USB host-pull remains an attended recovery path rather than
   an equal autonomous protocol.
10. Fleet-wide background observability and control is a product priority.
    Near-real-time background command execution is guaranteed for managed
    Android phones; iOS participates with durable but platform-scheduled
    background or foreground execution and no equivalent timing claim.
11. Managed Android phones are enrolled into an organization or venue with
    unique revocable device credentials. Fleet Operator commands require
    role-based authorization and durable audit records; local device UUIDs,
    shared venue secrets, and whichever human last signed in are not device
    authority.
12. Fleet control cannot force deletion or weaken clearance criteria. It may
    request a Clearance Evaluation, but the phone removes only the exact local
    bytes that match a valid Clearance Receipt; device-management wipe remains
    a separate administrative operation.

The canonical HydraCam terms live in the repository root `CONTEXT.md`; the
accepted safety boundary is recorded in
`docs/adr/0001-require-end-to-end-proof-before-automatic-clearance.md`.

## Existing Media Timeline Evidence

Annotations use the following labels:

- **Existing**: behavior found in current Media Timeline code or documentation.
- **Gap**: required behavior not established by the inspected contract.
- **Grill**: a genuine product or architecture decision for the other session.

### Phone Intake

- **Existing**:
  `backend/src/services/phoneIntakeRuntime.ts` hashes the phone-side candidate
  and imported file with SHA-256, compares the results, registers a hash alias
  in File Registry, resolves and materializes the registered file, links event
  media, records audit evidence, and restricts source deletion to verified
  items.
- **Existing**:
  phone intake models integrity, import, and source-deletion status per asset,
  so one batch already has item-level evidence rather than only one aggregate
  success flag.
- **Existing**:
  `backend/src/services/phoneIntakeAuditStore.ts` persists intake audit events.
- **Gap**:
  this is an attended host-side intake workflow, not yet a durable contract
  through which a HydraCam phone can obtain and later recover a Clearance
  Receipt.

### HydraCam Bridge

- **Existing**:
  `docs/reference/HYDRACAM_BRIDGE_API.md` defines session creation, direct
  upload start and completion, compatibility upload, File Registry identity,
  event linkage, and portable object-storage locators.
- **Existing**:
  the bridge uses event-scoped asset aliases to avoid basename-only collapse.
- **Gap**:
  the documented completion request does not bind the phone's SHA-256 and byte
  length to the registered object and event-media row.
- **Gap**:
  the documented completion response is not a recoverable, versioned Clearance
  Receipt contract.
- **Gap**:
  bridge status currently reports session identity and media counts, not
  authoritative per-asset clearance evidence.

## Media Timeline Requisites

The other-side grill should accept, reject, or sharpen each requisite
explicitly.

### Trust and Discovery

1. HydraCam must discover an approved Media Timeline endpoint without trusting
   arbitrary LAN responders or operator-entered lookalike hosts.
2. The production trust boundary must cover TLS, server identity, tenant or
   deployment identity, and the authority allowed to create or link events.
3. Upload authorization must be short-lived and least-privileged while still
   permitting unattended overnight resume after token expiry.
4. Receipt lookup must authenticate the device or account without requiring a
   long-lived bearer secret in HydraCam session metadata.

### Stable Identity and Idempotency

5. Every Sync Item needs a stable client-generated identity independent of
   filename, queue position, retry attempt, and charging cycle.
6. Upload start, part submission, object completion, File Registry
   registration, event linkage, and receipt issuance must all be idempotent.
7. Retrying an already accepted Sync Item must return the same accepted
   identity and proof rather than create duplicate objects or event-media rows.
8. An identity collision with different bytes must fail closed and surface as
   Needs Attention.

### Resumable Transfer

9. Large media must resume from durable acknowledged parts after network loss,
   unplug, app kill, reboot, authorization renewal, or backend restart.
10. Resume state must identify the exact source bytes; a changed file must not
    continue another file's multipart upload.
11. Expired signed URLs or session tokens must be renewable without discarding
    already accepted parts.
12. Abandoned multipart objects need bounded server-side cleanup that cannot
    remove a completed or receipted object.

### Integrity, Registration, and Event Linkage

13. Media Timeline must compare an independently established backend SHA-256
    and byte length with the phone-declared values after object finalization.
14. File Registry registration must resolve to the verified object through a
    portable locator.
15. The exact File Registry identity must be linked to the intended event and
    Event Capture Source before a Clearance Receipt is issued.
16. Receipt issuance must observe the registration and event linkage
    atomically, or use reconciliation semantics that cannot falsely attest a
    partially committed result.
17. Receipt lookup must remain possible after app reinstall, phone reboot,
    backend restart, and ordinary event metadata edits.
18. A later event rename, court correction, or participant edit must not
    invalidate a valid media linkage merely because descriptive metadata
    changed.

### Clearance Receipt

19. The receipt schema must be versioned and return, at minimum:
    - Sync Item identity;
    - device identity;
    - original filename or stable local identity;
    - SHA-256;
    - byte length;
    - File Registry file ID;
    - event ID;
    - Event Capture Source identity;
    - backend acceptance timestamp;
    - receipt version and stable receipt ID.
20. The receipt must be retrievable by stable Sync Item identity and must not
    depend on transient upload-session credentials.
21. Media Timeline supplies clearance evidence; HydraCam remains responsible
    for deciding which exact on-device Captured Original that evidence permits
    it to remove.
22. Receipt revocation or post-acceptance corruption discovery needs explicit
    semantics; silent mutation of an already issued receipt is prohibited.

### Partial Batches and Failure Isolation

23. Each valid Sync Item can receive its receipt independently; one corrupt,
    unattributed, or unsupported file must not erase successful evidence for
    its siblings.
24. Batch summaries must be projections over item evidence, never an alternate
    source of truth.
25. A partially successful phone must remain Needs Attention until every
    eligible item is cleared, explicitly retained, or excluded with a durable
    reason.
26. Backend reconciliation must distinguish retryable transfer failure,
    integrity mismatch, missing event attribution, registration failure,
    linkage failure, and permanent rejection.

### Fleet and Operations

27. Fleet views need per-phone counts and bytes for discovered, transferring,
    verified, linked, receipted, cleared-by-phone, retained, and failed items.
28. Backend observability must correlate device, Sync Item, upload session,
    object locator, File Registry ID, event ID, and receipt ID without logging
    credentials or unnecessary personal media metadata.
29. Operators need a reconciliation view for “bytes stored but no receipt” and
    “receipt issued but phone has not reported clearance.”
30. Retention and cleanup jobs must preserve receipted originals and audit
    evidence according to an explicit policy.

### Compatibility

31. Existing phone-intake and HydraCam bridge assets must converge on the same
    File Registry and event-media truth from a consumer perspective.
32. Compatibility multipart upload may remain a fallback only if it can produce
    the same integrity and receipt guarantees.
33. Existing `sessionGuid`, `deviceId`, capture timestamps, event IDs, and File
    Registry IDs must remain traceable through the new contract.
34. Legacy MoBo material must not be presented as clearance-safe unless the
    required integrity and linkage evidence actually exists.

## Candidate Receipt Shape for Grilling

This is an annotated conversation aid, not an accepted API schema:

```json
{
  "receiptVersion": 1,
  "receiptId": "stable-backend-issued-id",
  "syncItemId": "stable-client-issued-id",
  "acceptedAt": "2026-07-25T23:15:00.000Z",
  "original": {
    "filename": "VID_20260725_184201.mp4",
    "bytes": 4821930041,
    "sha256": "64-lowercase-hex-characters"
  },
  "registration": {
    "fileId": "file-registry-uuid",
    "portableLocator": "server-owned-portable-locator"
  },
  "attribution": {
    "eventId": "durable-event-id",
    "eventCaptureSourceId": "durable-event-source-id"
  },
  "acceptance": {
    "status": "accepted-for-clearance",
    "backendDeploymentId": "stable-trust-domain-id"
  }
}
```

Questions attached to this shape:

- **Grill**: Is an authenticated, durably queryable receipt sufficient, or must
  the receipt also carry a server signature verifiable offline?
- **Grill**: Which component independently computes the authoritative backend
  SHA-256: object storage, bridge worker, File Registry, or a dedicated
  verifier?
- **Grill**: Is event linkage committed in the same transaction as receipt
  issuance, or proven by a reconciliation barrier?
- **Grill**: Is a portable locator safe to expose to the phone, or should the
  receipt expose only the File Registry identity?
- **Grill**: What stable deployment or tenant identity prevents a development
  backend receipt from authorizing deletion in production?

## Scenarios the Media Timeline Grill Must Resolve

1. The phone finishes uploading at 02:00, its token expires, and it reboots
   before persisting the completion response.
2. Object storage has every byte, but File Registry registration fails.
3. File Registry registration succeeds, but event linkage fails.
4. The event does not exist when the phone begins Sync.
5. The operator selected the wrong event, but the mistake is discovered after
   the phone cleared its Captured Original.
6. Two phones submit identical bytes with the same filename for the same event.
7. One phone retries the same Sync Item after the backend already issued a
   receipt.
8. The backend receives a different file under an existing Sync Item identity.
9. Seven files are receipted and one has a checksum mismatch.
10. A receipted object is later found corrupt or missing in controlled storage.
11. A development Media Timeline instance is reachable on the venue LAN while
    the production endpoint is temporarily unavailable.
12. An operator needs to prove, weeks later, why one exact phone original was
    considered safe to clear.

## Suggested First Decision for the Other Grill

Start with the receipt trust model because it constrains endpoint discovery,
authentication, offline verification, recovery, and deletion safety:

1. Use an authenticated, durably queryable receipt within one pinned Media
   Timeline trust domain.
2. Use a cryptographically signed portable receipt verifiable offline by the
   HydraCam device.
3. Require both a signed receipt and successful online re-query immediately
   before clearance.
