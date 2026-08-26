# HydraCam User Flow FSM Diagrams

Last reviewed: 2026-06-18 (content dated 2026-06-18).
Last derived: 2026-06-14.

This document turns the user-flow tracker into finite-state-machine diagrams.
It keeps two layers separate:

1. App-facing user journeys inside the HydraCam Flutter app.
2. Cross-system relationship states between HydraCam mobile, the legacy
   HydraCam/MoBo service, and media-timeline.

Source evidence checked for this pass:

- `docs/control/user-flow-tracker.md`
- `docs/control/device-relationship-fsm.md`
- `docs/control/hydracam-mobo-media-timeline-merge-plan.md`
- `docs/control/cross-project-api-data-map.md`
- `lib/services/hydracam_api_service.dart`
- `lib/services/session_manager.dart`
- `lib/services/uploader_service.dart`
- `/Users/jose/src/work/mobo/KEOB_Motherboard_2_Web/Controllers/HydraCam/HydraCamApiController.cs`
- `/Users/jose/src/work/media-timeline/backend/src/routes/hydraCamBridge.ts`
- `/Users/jose/src/work/media-timeline/backend/src/routes/hydracamRoutes.ts`
- `/Users/jose/src/work/media-timeline/backend/src/routes/hydra.ts`

## Diagram Legend

| Marker | Meaning |
| --- | --- |
| `current` | Implemented path in the current app/service code. |
| `partial` | Code or tests exist, but the user/device flow is not fully proven. |
| `future` | Product-valid target that needs backend/media-timeline cutover work. |
| `blocked` | Known credential, device, service, or policy blocker. |

## App User Journey FSM

This is the top-level mobile journey from launch to review. It deliberately
keeps local capture durability before upload success, because the app must not
lose media when the service is slow, unavailable, or mid-cutover.

```mermaid
stateDiagram-v2
    [*] --> AppLaunch

    AppLaunch --> NeedsAuthentication: no usable user identity
    AppLaunch --> IdentityReady: existing usable identity
    NeedsAuthentication --> IdentityReady: Auth0 login succeeds
    NeedsAuthentication --> AuthBlocked: login, restore, or logout path fails
    AuthBlocked --> NeedsAuthentication: user retries

    IdentityReady --> VenueSelection: sports centers and courts requested
    VenueSelection --> VenueReady: sports center and court selected
    VenueSelection --> VenueBlocked: service unavailable or no valid court
    VenueBlocked --> VenueSelection: retry or cached/manual selection

    VenueReady --> CameraSetup: operator opens setup/preview
    CameraSetup --> CameraReady: lens, profile, and leveling accepted
    CameraSetup --> CameraBlocked: permission, plugin, or hardware failure
    CameraBlocked --> CameraSetup: permission/device retry

    CameraReady --> RoleDecision
    RoleDecision --> SingleDeviceMaster: operator uses this device alone
    RoleDecision --> MasterDiscovery: operator waits for an existing master
    RoleDecision --> MasterActive: operator explicitly starts master

    MasterDiscovery --> SlaveConnected: master discovered or assigned
    MasterDiscovery --> MasterActive: auto-promotion timeout
    MasterDiscovery --> NetworkBlocked: LAN/local-control not ready
    NetworkBlocked --> MasterDiscovery: network recovers

    SingleDeviceMaster --> MasterActive
    SlaveConnected --> SessionParticipantReady
    MasterActive --> SessionAuthorityReady

    SessionAuthorityReady --> BackendSessionCreating: create session through service
    BackendSessionCreating --> SessionActive: backend session GUID returned
    BackendSessionCreating --> SessionBlocked: service rejected or unreachable
    SessionBlocked --> BackendSessionCreating: retry create session

    SessionParticipantReady --> SessionActive: sessionStatus received
    SessionActive --> CaptureCommandReady

    CaptureCommandReady --> PhotoCapture: take photo
    CaptureCommandReady --> VideoRecording: start video
    PhotoCapture --> LocalMediaSaved: photo saved and metadata updated
    VideoRecording --> LocalMediaSaved: stop video, save file and metadata

    LocalMediaSaved --> UploadQueuePending: service session exists
    LocalMediaSaved --> UploadBlocked: no service session
    UploadBlocked --> ServiceSessionCreating: create or rejoin service session

    UploadQueuePending --> Uploading: auto or manual upload starts
    Uploading --> Uploaded: service confirms upload
    Uploading --> UploadFailed: network/service/file error
    Uploaded --> CaptureCommandReady: continue session
    UploadFailed --> UploadQueuePending: retry or manual upload
    UploadQueuePending --> CaptureCommandReady: upload deferred

    CaptureCommandReady --> SessionEnding: operator ends session
    SessionEnding --> ReviewHistory: metadata closed and uploader reset
    ReviewHistory --> [*]
```

Primary release gaps:

- `UF-04`: true attended two-device master/slave capture and upload evidence.
- `UF-07`: explicit production policy for reconnect and master loss.
- `UF-13`: cutover from legacy MoBo upload to media-timeline bridge.

## Role And Relationship FSM

The detailed current-code device relationship FSM lives in
`docs/control/device-relationship-fsm.md`. This reduced version shows how the
user journey depends on that relationship state.

```mermaid
stateDiagram-v2
    [*] --> LocalControlCheck

    LocalControlCheck --> RelationshipBlocked: permissions or local network unavailable
    RelationshipBlocked --> LocalControlCheck: readiness restored

    LocalControlCheck --> DiscoveringMaster: default auto-slave launch
    LocalControlCheck --> AutomationStandby: automation standby launch
    LocalControlCheck --> MasterStarting: manual master launch

    AutomationStandby --> MasterStarting: automation set_role(master)
    AutomationStandby --> SlaveConnecting: automation set_role(slave, preferredMasterIp)

    DiscoveringMaster --> SlaveConnecting: UDP master broadcast discovered
    DiscoveringMaster --> MasterStarting: no master before timeout
    SlaveConnecting --> SlaveConnectedIdle: WebSocket opens, no session
    SlaveConnecting --> SlaveConnectedSession: WebSocket opens, sessionStatus received
    SlaveConnecting --> RecoveringRelationship: connection fails

    MasterStarting --> MasterIdle: WebSocket server bound and announcer active
    MasterIdle --> MasterSessionActive: session created or restored
    MasterSessionActive --> MasterRecording: recording command active
    MasterRecording --> MasterSessionActive: recording stopped and media saved
    MasterSessionActive --> MasterIdle: session ended

    SlaveConnectedIdle --> SlaveConnectedSession: sessionStarted/sessionStatus
    SlaveConnectedSession --> SlaveRecording: startRecordingVideo
    SlaveRecording --> SlaveConnectedSession: stopRecordingVideo and local save
    SlaveConnectedSession --> SlaveConnectedIdle: sessionEnded/noSession

    SlaveConnectedIdle --> MasterMissing: socket closed or heartbeat path fails
    SlaveConnectedSession --> MasterMissing: socket closed or heartbeat path fails
    SlaveRecording --> MasterMissingWhileRecording: socket closed while recording

    MasterMissing --> RecoveringRelationship: restart discovery or explicit-IP retry
    MasterMissingWhileRecording --> RecordingRecoveryPolicyMissing: current production policy not explicit
    RecordingRecoveryPolicyMissing --> RecoveringRelationship: local save then await authority

    RecoveringRelationship --> DiscoveringMaster: normal auto mode
    RecoveringRelationship --> SlaveConnecting: forced preferred master IP
    RecoveringRelationship --> MasterStarting: current timeout auto-promotes
```

Risk to keep visible: current timeout auto-promotion can create split-brain
masters if several idle slaves lose the same master. Runtime automation avoids
this by explicitly choosing the promoted master and assigning every slave.

## Session And Upload FSM

This diagram describes the local app state around `SessionManager`,
`UploaderService`, and the current `HydraCamApiService`.

```mermaid
stateDiagram-v2
    [*] --> NoSession

    NoSession --> CreatingServiceSession: master calls service create-session
    CreatingServiceSession --> ServiceSessionActive: service returns session GUID
    CreatingServiceSession --> SessionCreateFailed: create-session fails
    SessionCreateFailed --> CreatingServiceSession: retry

    ServiceSessionActive --> CapturingPhoto: photo command
    ServiceSessionActive --> RecordingVideo: video command
    CapturingPhoto --> MediaMetadataWriting
    RecordingVideo --> MediaMetadataWriting

    MediaMetadataWriting --> SyncSidecarWriting: sync metadata available
    MediaMetadataWriting --> QueueEligibilityCheck: no sync metadata
    SyncSidecarWriting --> QueueEligibilityCheck

    QueueEligibilityCheck --> UploadBlocked: no active service session
    QueueEligibilityCheck --> UploadQueued: service session is active

    UploadQueued --> UploadDeferred: auto-upload disabled
    UploadDeferred --> Uploading: manual upload
    UploadQueued --> Uploading: auto-upload enabled

    Uploading --> UploadSucceeded: service accepted media
    Uploading --> UploadFailed: service, network, or file failure
    Uploading --> UploadCancelled: user cancels active upload

    UploadSucceeded --> LocalDeleteCheck: metadata updated
    LocalDeleteCheck --> LocalMediaDeleted: delete-after-upload enabled
    LocalDeleteCheck --> BackendSessionActive: local retention enabled
    LocalMediaDeleted --> BackendSessionActive

    UploadFailed --> UploadQueued: retry
    UploadCancelled --> UploadQueued: requeue or retry later
    UploadBlocked --> BackendSessionActive: backend session restored or recreated

    BackendSessionActive --> EndingSession: operator ends session
    EndingSession --> NoSession: metadata closed and uploader reset
```

Important current behavior:

- Upload is blocked if the session was not created or joined as a backend
  session.
- Local file and metadata writes happen before the upload queue is drained.
- The mobile app still targets `https://hydracam.azurewebsites.net/api`.

## Current Mobile To HydraCam Service FSM

This is the current production-shaped path: mobile uploads to the legacy
HydraCam/MoBo service. media-timeline only sees the result later through
legacy scan/import routes.

```mermaid
stateDiagram-v2
    [*] --> MobileIdentityReady

    MobileIdentityReady --> VenueLookupRequested: GET sportscenters/courts
    VenueLookupRequested --> VenueLookupReady: MoBo returns venue data
    VenueLookupRequested --> VenueLookupFailed: auth or service failure
    VenueLookupFailed --> VenueLookupRequested: retry

    VenueLookupReady --> MobileCreateSessionRequested: POST sessions/create
    MobileCreateSessionRequested --> MoBoSessionCreated: MoBo writes HydraCamSession
    MobileCreateSessionRequested --> CreateSessionRejected: invalid court/user/session
    CreateSessionRejected --> MobileCreateSessionRequested: retry with corrected inputs

    MoBoSessionCreated --> MobileBackendSessionBound: app stores session GUID
    MobileBackendSessionBound --> LocalCaptureDurable: app saves photo/video and metadata
    LocalCaptureDurable --> MobileUploadRequested: POST sessions/upload-media

    MobileUploadRequested --> MoBoMediaStored: MoBo writes photo/video row and Azure Blob
    MobileUploadRequested --> UploadRejected: missing session, bad file, or service error
    UploadRejected --> MobileUploadRequested: retry queue item

    MoBoMediaStored --> MobileUploadConfirmed: app marks media uploaded
    MobileUploadConfirmed --> MoreCaptureOrEnd
    MoreCaptureOrEnd --> LocalCaptureDurable: more media
    MoreCaptureOrEnd --> MobileEndSessionRequested: POST sessions/end

    MobileEndSessionRequested --> MoBoSessionEnded: MoBo writes EndTime
    MoBoSessionEnded --> LegacyPortalAvailable: Details page and Blob links exist
    LegacyPortalAvailable --> [*]
```

State ownership:

| State family | Owner today | Durable key |
| --- | --- | --- |
| Capture files and `metadata.json` | HydraCam mobile | `sessionGuid` plus media paths |
| Backend session row | MoBo HydraCam service | `HydraCamSession.Guid` |
| Uploaded blobs | Azure Blob through MoBo | `hydracam/<sessionGuid>/...` |
| User-visible legacy detail page | MoBo portal | numeric session ID |

## Current Media-Timeline Legacy Import FSM

This is the current relationship after legacy mobile uploads exist. It is a
read/import/process path, not the direct mobile upload path.

```mermaid
stateDiagram-v2
    [*] --> LegacyPortalCandidate

    LegacyPortalCandidate --> ScanRequested: POST /api/hydracam/scan
    ScanRequested --> IndexedLegacySession: hydracam_sessions index updated
    ScanRequested --> ScanFailed: portal or range failure
    ScanFailed --> ScanRequested: retry scan

    IndexedLegacySession --> LocalStatusChecked: POST /api/hydracam/sessions/local-status
    LocalStatusChecked --> AlreadyInTimeline: event_media rows already exist
    LocalStatusChecked --> NeedsImport: missing local event/media rows

    NeedsImport --> ImportRequested: POST /api/hydracam/ingest/:id or /api/hydra/import/:sessionId
    ImportRequested --> ManifestBuilt: portal and Blob links resolved
    ImportRequested --> ImportFailed: details page, blob, or registry failure
    ImportFailed --> ImportRequested: resume or retry

    ManifestBuilt --> RegistryRegistered: File Registry records source media
    RegistryRegistered --> EventMediaLinked: events, event_media, devices, mirror rows written
    EventMediaLinked --> ProcessingOptional: import complete

    ProcessingOptional --> ProcessingQueued: POST /api/hydra/:sessionId/process
    ProcessingQueued --> TimelineReady: CV/AI outputs and timeline available
    ProcessingOptional --> TimelineReady: no processing requested
    AlreadyInTimeline --> TimelineReady
```

State ownership:

| State family | Owner today | Durable key |
| --- | --- | --- |
| Legacy session index | media-timeline | MoBo numeric session ID |
| File resolution | File Registry v2 | file ID plus source locator |
| Canonical review data | media-timeline | event ID and `event_media` rows |
| Processing/timeline outputs | media-timeline CV/AI services | event/session IDs |

## Target Direct Bridge FSM

This is the intended cutover path from the merge plan. It should replace new
mobile-to-MoBo uploads only after the bridge contract is proven end to end.

```mermaid
stateDiagram-v2
    [*] --> BridgeTargetConfigured

    BridgeTargetConfigured --> BridgeCreateSessionRequested: POST /api/hydracam-bridge/sessions or compat create
    BridgeCreateSessionRequested --> BridgeSessionCreated: event, mirror session, upload token returned
    BridgeCreateSessionRequested --> BridgeCreateFailed: invalid payload, auth, or storage config
    BridgeCreateFailed --> BridgeCreateSessionRequested: retry after correction

    BridgeSessionCreated --> MobileBridgeSessionBound: app stores bridge session GUID/event IDs
    MobileBridgeSessionBound --> LocalCaptureDurable: app saves local media and metadata

    LocalCaptureDurable --> BridgeUploadStartRequested: POST /sessions/:sessionGuid/uploads/start
    BridgeUploadStartRequested --> ObjectUploadReady: object key and media-storage paths returned
    BridgeUploadStartRequested --> BridgeUploadStartFailed: upload token or payload failure
    BridgeUploadStartFailed --> BridgeUploadStartRequested: retry

    ObjectUploadReady --> ObjectUploadInProgress: multipart start, sign, upload parts
    ObjectUploadInProgress --> ObjectUploadComplete: multipart complete
    ObjectUploadInProgress --> ObjectUploadFailed: part/sign/storage failure
    ObjectUploadFailed --> ObjectUploadReady: retry or abort/restart

    ObjectUploadComplete --> BridgeCompleteRequested: POST /uploads/complete
    BridgeCompleteRequested --> FileRegistryLinked: File Registry ID linked
    FileRegistryLinked --> EventMediaLinked: event_media, devices, mirror asset rows written
    EventMediaLinked --> MobileUploadConfirmed: app marks media uploaded

    MobileUploadConfirmed --> MoreCaptureOrEnd
    MoreCaptureOrEnd --> LocalCaptureDurable: more media
    MoreCaptureOrEnd --> BridgeEndSessionRequested: compat end or bridge end
    BridgeEndSessionRequested --> BridgeSessionEnded: session closed in media-timeline
    BridgeSessionEnded --> TimelineProcessable: event can enter review/CV/AI flow
    TimelineProcessable --> [*]
```

Cutover guardrail: do not move the mobile app to the bridge until media-timeline
tests prove one photo and one video create the expected event, File Registry,
`event_media`, device, and mirror rows.

## Cross-System State Relationship

This diagram shows how the same real-world capture moves across state owners.
The left-to-right progression is logical ownership, not necessarily a single
request chain.

```mermaid
stateDiagram-v2
    [*] --> UserWantsRecording

    UserWantsRecording --> MobileReady: identity, venue, camera, role ready
    MobileReady --> MobileSessionActive: backend session bound
    MobileSessionActive --> MobileMediaDurable: local files, metadata, sidecars

    MobileMediaDurable --> LegacyServicePath: current app target
    MobileMediaDurable --> DirectBridgePath: target app target

    LegacyServicePath --> MoBoSessionAndMedia: MoBo DB plus Azure Blob
    MoBoSessionAndMedia --> LegacyImportAvailable: media-timeline can scan/import
    LegacyImportAvailable --> TimelineCanonicalized: File Registry and event_media rows

    DirectBridgePath --> BridgeSessionAndMedia: media-timeline bridge receives upload
    BridgeSessionAndMedia --> TimelineCanonicalized: File Registry and event_media rows

    TimelineCanonicalized --> ProcessingReady: manifest/timeline inputs available
    ProcessingReady --> AIAndTimelineReady: CV/AI outputs and timeline review
    AIAndTimelineReady --> [*]
```

Relationship rules:

- The mobile app owns capture reliability and local durability.
- The legacy HydraCam/MoBo service owns historical compatibility and current
  deployed API behavior.
- media-timeline owns new canonical event/media/timeline/AI state.
- `sessionGuid` is the stable cross-system key; numeric MoBo IDs are legacy
  provenance keys.
- Role-only multi-device proof is not upload proof, and upload proof is not
  media-timeline processing proof.

## Validation And Maintenance

Use this document with `docs/control/user-flow-tracker.md`:

1. Update the tracker status first when evidence changes.
2. Update these diagrams when a state or ownership boundary changes.
3. For docs-only edits, run `git diff --check`.
4. For mobile behavior changes, follow the validation tier in
   `docs/control/regular-evaluation-plan.md`.

## Next Implementation Decisions

1. Decide whether production master authority is manual, deterministic local
   election, or backend-led.
2. Prove `UF-04` with a true two-device master/slave capture and upload run.
3. Finish the media-timeline bridge acceptance test before changing the mobile
   API target.
4. Add bridge configurability to `HydraCamApiService` only after the target
   direct bridge FSM has a passing backend proof.
