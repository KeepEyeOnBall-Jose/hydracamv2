# Cross-Project API And Data Map

Last reviewed: 2026-06-12.

This document visualizes how HydraCam mobile, the MoBo HydraCam webservice, and
media-timeline relate at the API, endpoint, storage, and ownership layers.
For the user-flow and cross-system finite-state-machine view, see
`user-flow-fsm-diagrams.md`.

Legend:

- `current`: implemented/currently used path.
- `in progress`: code exists but is not fully cut over or verified end to end.
- `target`: intended direction from the merge plan.
- `legacy`: retained for historical data and compatibility.

## System Context

```mermaid
flowchart LR
  Mobile["HydraCam mobile app<br/>/Users/jose/src/work/hydracamv2<br/>Flutter capture, local queue, device roles"]
  LocalStore[("Mobile local storage<br/>session_GUID/metadata.json<br/>photos/videos<br/>*.sync.json sidecars")]
  MoBo["MoBo HydraCam webservice<br/>/Users/jose/src/work/mobo<br/>ASP.NET api/hydracam"]
  MoBoDb[("MoBo SQL data<br/>HydraCamSessions<br/>HydraCamPhotos<br/>HydraCamVideos<br/>Courts, SportsCenters, Users")]
  AzureBlob[("Azure Blob storage<br/>keob2/hydracam/session-guid/...")]
  AzurePortal["Legacy portal<br/>hydracam.azurewebsites.net<br/>HydraCam/Details/id"]
  MT["media-timeline<br/>/Users/jose/src/work/media-timeline<br/>event, file, timeline, CV/AI backend"]
  MTDb[("media-timeline SQLite<br/>events, event_media<br/>devices, event_devices<br/>hydracam_mirror_*<br/>hydracam_sessions, ingested_sessions")]
  FileRegistry[("File Registry v2<br/>file ids, aliases, locations")]
  ObjectStorage[("Object storage<br/>s3-compatible locators<br/>target new uploads")]
  CV["CV/AI services<br/>pose, racket, ball, sync, timeline"]

  Mobile -->|"current API base<br/>https://hydracam.azurewebsites.net/api"| MoBo
  Mobile -->|"records first"| LocalStore
  MoBo -->|"EF writes"| MoBoDb
  MoBo -->|"media blobs"| AzureBlob
  AzurePortal -->|"detail pages and links"| AzureBlob
  MT -->|"legacy scrape/import current"| AzurePortal
  MT -->|"register remote or materialized files"| FileRegistry
  MT -->|"canonical event rows"| MTDb
  MT -->|"processing jobs"| CV
  FileRegistry -->|"resolves media"| CV
  MT -.->|"target direct bridge<br/>/api/hydracam-bridge"| Mobile
  Mobile -.->|"target multipart/object upload"| ObjectStorage
  ObjectStorage -.->|"registered as s3 locator"| FileRegistry
```

## Current Mobile To MoBo API Flow

This is the live mobile path today. The Flutter app records locally first, then
uses the legacy API base `https://hydracam.azurewebsites.net/api`.

```mermaid
sequenceDiagram
  participant App as HydraCam mobile
  participant Local as Mobile local files
  participant Auth as M2M Auth0 helper
  participant Api as MoBo HydraCam API
  participant Db as MoBo SQL
  participant Blob as Azure Blob hydracam container

  App->>Auth: get bearer token
  App->>Api: GET /sportscenters
  Api->>Db: read SportsCenters and court counts
  Api-->>App: sports center list

  App->>Api: GET /courts?sportsCenterGuid=...
  Api->>Db: read Courts joined to SportsCenters
  Api-->>App: courts

  App->>Api: POST /sessions/create?courtGuid=...&userGuid=...
  Note over App,Api: body includes SessionId and StartTime
  Api->>Db: create HydraCamSession and session-user link
  Api-->>App: Id, Guid, CourtId

  App->>Local: write session_GUID/metadata.json
  App->>Local: save CapturedPhoto/CapturedVideo files
  App->>Local: write optional media.sync.json sidecars

  App->>Api: POST /sessions/upload-media?sessionGuid=...&isPhoto=true|false
  Note over App,Api: multipart field files plus slaveDeviceId, captureDate, receivedDate, appVersion, appBuildNumber
  Api->>Db: create HydraCamPhoto or HydraCamVideo records
  Api->>Blob: store hydracam/session-guid/photos-or-videos/file
  Api-->>App: upload success

  App->>Api: POST /sessions/end?sessionGuid=...
  Api->>Db: set HydraCamSession.EndTime
  Api-->>App: Id and EndTime
```

### Current Mobile Endpoint Calls

| Mobile method | Current endpoint path | Purpose | Data sent |
| --- | --- | --- | --- |
| `fetchSportsCenters()` | `GET /sportscenters` | Venue discovery | bearer token |
| `fetchCourts()` | `GET /courts?sportsCenterGuid=...` | Court discovery | sports-center GUID |
| `fetchSessions()` | `GET /sessions?courtGuid=...` | Legacy session list for a court | court GUID |
| `createSession()` | `POST /sessions/create?courtGuid=...&userGuid=...` | Create backend session | `SessionId`, `StartTime` |
| `uploadMedia()` | `POST /sessions/upload-media?sessionGuid=...&isPhoto=...` | Upload photo or video | multipart `files`, device ID, capture/received timestamps, app version/build |
| `endSession()` | `POST /sessions/end?sessionGuid=...` | End backend session | session GUID |
| `notifyReadyToTransmit()` | `POST /device/ReadyToTransmit` | Legacy streaming readiness marker | `DeviceId`, `SessionGuid` |

Note: the mobile source also has a user lookup contract for
`users/get-by-email`; the inspected MoBo controller exposes `GetUserByEmail`.
Treat this as a route-alias/deployed-contract item to verify before cutover.

## Existing media-timeline Legacy Import Flow

This is the existing backfill and processing path. It imports MoBo/Azure
sessions into media-timeline rather than receiving fresh mobile uploads.

```mermaid
sequenceDiagram
  participant UI as HydraCam Explorer
  participant MT as media-timeline API
  participant Client as HydraCamClient
  participant Portal as hydracam.azurewebsites.net
  participant Blob as Azure Blob
  participant Registry as File Registry v2
  participant Db as media-timeline SQLite
  participant CV as CV/AI jobs

  UI->>MT: GET /api/hydracam/sessions
  MT->>Db: read hydracam_sessions index
  MT-->>UI: indexed sessions

  UI->>MT: POST /api/hydracam/scan
  MT->>Portal: fetch Details pages over session ID range
  Portal-->>MT: session metadata and blob links
  MT->>Db: update hydracam_sessions

  UI->>MT: POST /api/hydracam/ingest/:id or /api/hydra/import/:sessionId
  MT->>Client: fetch session detail and media links
  Client->>Portal: GET /HydraCam/Details/id
  Portal-->>Client: photos/videos and Azure links
  Client->>Blob: optional HEAD/materialize source media
  MT->>Registry: register source=hydracam or materialized media
  Registry-->>MT: fileId, videoId, locations
  MT->>Db: upsert events and event_media
  MT->>Db: upsert devices and event_devices
  MT->>Db: upsert hydracam_mirror_sessions and hydracam_mirror_assets

  UI->>MT: POST /api/hydra/:sessionId/process or /run-analyses
  MT->>CV: enqueue pose, racket, ball, sync, timeline work
  CV->>Registry: resolve fileId and media locations
  CV->>Db: write processing outputs/status
  UI->>MT: GET /api/hydra/:sessionId/timeline
  MT-->>UI: timeline data
```

### media-timeline Legacy Endpoints

| Route family | Endpoint | Purpose |
| --- | --- | --- |
| `/api/hydracam` | `GET /sessions` | List indexed legacy HydraCam sessions |
| `/api/hydracam` | `POST /sessions/local-status` | Cross-check indexed sessions against local events/media |
| `/api/hydracam` | `POST /sessions/refresh-remote` | Refresh remote session metadata |
| `/api/hydracam` | `POST /scan`, `GET /scan/status` | Scan legacy portal session IDs |
| `/api/hydracam` | `POST /ingest/:id` | Ingest and optionally process one session |
| `/api/hydracam` | `POST /ingest-local/:id` | Register locally without processing |
| `/api/hydracam` | `POST /ingest/batch`, `POST /ingest/auto` | Bulk ingestion |
| `/api/hydra` | `POST /import/:sessionId` | Import one legacy session |
| `/api/hydra` | `POST /:sessionId/resume` | Resume ingestion/download/processing |
| `/api/hydra` | `POST /:sessionId/process` | Trigger CV processing jobs |
| `/api/hydra` | `GET /:sessionId/manifest` | Inspect session manifest |
| `/api/hydra` | `GET /:sessionId/timeline` | Get event timeline view |
| `/api/hydra` | `GET /:sessionId/status` | Get ingestion/process status |

## Target Direct Bridge Flow

This is the intended cutover path. It is partially implemented in
media-timeline, but HydraCam mobile has not been switched to it yet.

```mermaid
sequenceDiagram
  participant App as HydraCam mobile
  participant Local as Mobile local files
  participant Bridge as media-timeline bridge API
  participant Storage as /api/media-storage and object storage
  participant Registry as File Registry v2
  participant Db as media-timeline SQLite
  participant UI as media-timeline UI
  participant CV as CV/AI jobs

  App->>Bridge: POST /sessions
  Note over App,Bridge: sessionGuid or sessionId, court/user metadata, startedAt
  Bridge->>Db: create or mirror event and hydracam_mirror_session
  Bridge-->>App: eventId, sessionGuid, uploadToken, upload paths

  App->>Local: keep durable local recording and queue

  App->>Bridge: POST /sessions/:sessionGuid/uploads/start
  Note over App,Bridge: bearer uploadToken
  Bridge-->>App: objectKey and media-storage paths

  App->>Storage: POST /multipart/start
  Storage-->>App: uploadId and object key
  App->>Storage: POST /multipart/sign-part
  Storage-->>App: signed part URL
  App->>Storage: upload bytes to signed URL
  App->>Storage: POST /multipart/complete
  Storage->>Registry: register source=s3 locator and aliases
  Storage-->>App: registered fileId

  App->>Bridge: POST /sessions/:sessionGuid/uploads/complete
  Note over App,Bridge: fileId or portable source+locator, kind, deviceId, capturedAt, metadata
  Bridge->>Db: upsert event_media
  Bridge->>Db: upsert devices and event_devices
  Bridge->>Db: upsert hydracam_mirror_assets
  Bridge-->>App: bridge registration result

  UI->>Bridge: GET /sessions/:sessionGuid/status
  Bridge->>Db: read event/media/mirror rows
  Bridge-->>UI: counts and event id

  UI->>CV: trigger processing from media-timeline event
  CV->>Registry: resolve File Registry locations
```

### Bridge And Object Storage Endpoints

| Route family | Endpoint | Purpose | Status |
| --- | --- | --- | --- |
| `/api/hydracam-bridge` | `POST /sessions` | Create/mirror a capture session as a media-timeline event | in progress |
| `/api/hydracam-bridge` | `POST /sessions/:sessionGuid/uploads/start` | Return object key and storage paths | in progress |
| `/api/hydracam-bridge` | `POST /sessions/:sessionGuid/uploads/complete` | Link completed media into event/media/mirror tables | in progress |
| `/api/hydracam-bridge` | `GET /sessions/:sessionGuid/status` | Read bridge session status and counts | in progress |
| `/api/hydracam-bridge` | `POST /compat/sessions/create` | Compatibility shape for current mobile create-session call | in progress |
| `/api/hydracam-bridge` | `POST /compat/sessions/end` | Compatibility shape for current mobile end-session call | in progress |
| `/api/hydracam-bridge` | `POST /compat/sessions/upload-media` | Compatibility shape for current multipart upload | in progress |
| `/api/media-storage` | `GET /status` | Check object-storage configuration | current |
| `/api/media-storage` | `POST /multipart/start` | Start object-storage multipart upload | current |
| `/api/media-storage` | `POST /multipart/sign-part` | Sign one upload part | current |
| `/api/media-storage` | `POST /multipart/complete` | Complete upload and optionally register File Registry row | current |
| `/api/media-storage` | `POST /multipart/abort` | Abort multipart upload | current |
| `/api/media-storage` | `POST /read-url` | Get read URL from fileId or locator | current |

## Data Ownership Map

```mermaid
flowchart TB
  subgraph MobileApp["HydraCam mobile local state"]
    MobileSession[("CaptureSession<br/>sessionId, sessionGuid<br/>deviceType, debugSession")]
    MobileMedia[("CapturedPhoto and CapturedVideo<br/>local path, deviceId<br/>capture/received times<br/>upload status")]
    MobileMetadata[("session_GUID/metadata.json<br/>photos/videos arrays<br/>sync/capture context")]
    MobileSidecars[("media.sync.json sidecars<br/>clock and sync metadata")]
  end

  subgraph MoBoLegacy["MoBo legacy webservice state"]
    MoBoSessions[("HydraCamSessions<br/>Guid, SessionId<br/>StartTime, EndTime<br/>CourtId")]
    MoBoMedia[("HydraCamPhotos<br/>HydraCamVideos<br/>Name, BlobPath, timestamps<br/>SlaveDeviceId")]
    MoBoVenue[("Courts, SportsCenters<br/>HydraCamUsers<br/>HydraCamSessionUsers")]
    BlobStore[("Azure Blob<br/>hydracam/session-guid/photos<br/>hydracam/session-guid/videos")]
  end

  subgraph MediaTimeline["media-timeline canonical state"]
    Events[("events<br/>event id, session_guid<br/>court/venue metadata<br/>counts and timing")]
    EventMedia[("event_media<br/>file_id, kind, filename<br/>source_id, captured_at<br/>duration/fps/size<br/>perspective labels")]
    Devices[("devices and event_devices<br/>hydracam:deviceId<br/>metadata, offsets, trust")]
    Mirror[("hydracam_mirror_sessions<br/>hydracam_mirror_assets<br/>payload provenance")]
    Index[("hydracam_sessions<br/>ingested_sessions<br/>legacy scan/index state")]
    Jobs[("hydra_analysis_jobs<br/>processing status")]
    Registry[("File Registry v2<br/>fileId, aliases<br/>source locator locations")]
  end

  MobileSession --> MobileMetadata
  MobileMedia --> MobileMetadata
  MobileMedia --> MobileSidecars

  MobileSession -->|"current create/upload/end"| MoBoSessions
  MobileMedia -->|"current multipart upload"| MoBoMedia
  MoBoMedia --> BlobStore
  MoBoVenue --> MoBoSessions

  MoBoSessions -->|"legacy import/backfill"| Index
  BlobStore -->|"source=hydracam location"| Registry
  Registry --> EventMedia
  MoBoSessions -->|"mapped as event"| Events
  MoBoMedia -->|"provenance"| Mirror
  EventMedia --> Events
  Devices --> Events
  Jobs --> Events

  MobileSession -.->|"target direct bridge"| Events
  MobileMedia -.->|"target direct bridge"| Registry
  MobileMedia -.->|"target metadata"| EventMedia
```

## Endpoint And Storage Responsibility Matrix

| Component | Owns APIs | Stores | Should own going forward |
| --- | --- | --- | --- |
| HydraCam mobile | Local WebSocket master/slave control; outbound calls to backend API | Local app documents, session metadata, photo/video files, sync sidecars, upload queue status | Capture reliability, device orchestration, local durable media until backend confirms upload |
| MoBo HydraCam | `api/hydracam/CreateSession`, `UploadMedia`, `EndSession`, `device/ReadyToTransmit`, `courts`, `sessions`, `sportscenters`, `GetUserByEmail` | SQL Server HydraCam tables and Azure Blob media | Legacy compatibility and historical provenance only |
| media-timeline legacy import | `/api/hydracam/*`, `/api/hydra/*` | `hydracam_sessions`, `ingested_sessions`, event rows, File Registry locations, mirror tables, processing jobs | Backfill, reconciliation, and processing for old MoBo/Azure sessions |
| media-timeline bridge | `/api/hydracam-bridge/*` | Canonical events, event media, devices, mirror rows, File Registry IDs | New direct app session/upload path after proof |
| media-timeline storage | `/api/media-storage/*` | Object-storage locators and File Registry registrations | Large video upload and signed URL boundary |
| media-timeline CV/AI | Processing and timeline APIs/jobs | Derived labels, tracks, sync results, analysis status | Timeline, AI, review, derived media, and product retrieval |

## Cutover Boundary

The mobile app should not move from MoBo to media-timeline until the backend
bridge passes these checks:

```mermaid
flowchart LR
  A["Bridge backend schemas pass"] --> B["Direct or compat upload creates event"]
  B --> C["File Registry row exists"]
  C --> D["event_media row exists"]
  D --> E["device and event_device rows exist"]
  E --> F["hydracam_mirror rows preserve source payload"]
  F --> G["HydraCam Explorer shows app-originated session"]
  G --> H["Real mobile device uploads one photo and one video"]
  H --> I["media-timeline timeline and processing can consume the files"]
```

## Known Gaps

- HydraCam mobile still targets the legacy Azure API base.
- MoBo has no media-timeline bridge integration and should remain legacy.
- The media-timeline bridge branch has in-progress work and must be validated
  before mobile cutover.
- The `Alicia video-store API` is currently a plan, not implemented route code.
- The user-lookup route naming differs between inspected mobile source and
  inspected MoBo controller; verify the deployed alias before changing mobile.
