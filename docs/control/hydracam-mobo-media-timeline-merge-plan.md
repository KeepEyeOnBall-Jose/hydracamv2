# HydraCam, MoBo, And Media Timeline Merge Plan

Last reviewed: 2026-06-08.

This plan covers three active codebases:

- `/Users/jose/src/work/hydracamv2`: HydraCam Flutter mobile app and
  real-device capture/runtime validation.
- `/Users/jose/src/work/mobo`: legacy MoBo webservice that contains the
  original HydraCam portal, API, EF models, SQL Server context, and Azure Blob
  storage integration.
- `/Users/jose/src/work/media-timeline`: event, media, File Registry, timeline,
  CV/AI, and HydraCam import/indexing system.

Interpretation note: "hydrcam" is treated here as the active Flutter repo,
`/Users/jose/src/work/hydracamv2`.

## Executive Decision

Do a product and data-plane merge, not a physical repository merge.

Keep HydraCam mobile as the capture app. Make media-timeline the canonical
backend for new sports events, media assets, processing, timeline review, and
AI outputs. Keep MoBo HydraCam as the legacy source of truth for historical
HydraCam sessions until those sessions are mirrored, reconciled, and proven in
media-timeline.

The right shape is a hybrid bridge:

1. Media-timeline owns new canonical events, media files, event devices,
   timelines, derived assets, and processing results.
2. MoBo remains compatibility/backfill for existing `hydracam.azurewebsites.net`
   sessions and Azure Blob URLs.
3. HydraCam mobile uploads new sessions to a media-timeline bridge after the
   bridge proves it accepts the current app contract.
4. The app keeps local durable recording/upload queue behavior, because capture
   reliability matters more than backend elegance.

## Source Evidence Inspected

HydraCam mobile:

- `lib/services/hydracam_api_service.dart`: current hardcoded API base and
  app-facing session/upload/user/court methods.
- `lib/services/uploader_service.dart`: local queue and auto/manual upload
  behavior.
- `lib/services/session_manager.dart`: local session metadata, media tracking,
  and upload queue handoff.
- `docs/control/status-and-roadmap.md`: current mobile status and real-device
  validation posture.

MoBo HydraCam:

- `KEOB_Motherboard_2_Web/Controllers/HydraCam/HydraCamApiController.cs`:
  legacy API for session creation, media upload, session end, users, courts,
  and sports centers.
- `KEOB_Motherboard_2_Web/Controllers/HydraCam/HydraCamController.cs`:
  portal/admin CRUD and manual upload views.
- `KEOB_Motherboard_2_Web/Models/HydraCam/HydraCamSession.cs`: SQL Server
  entities for sessions, photos, videos, sub-sessions, courts, users, and
  drive links.
- `KEOB_Motherboard_2_Web/Shared/Data/HydraCamDbContext.cs`: HydraCam DB set
  ownership.
- `KEOB_Motherboard_2_Web/Program.cs`: Auth0/JWT, HydraCam DB, form upload
  limits, and credential risk area.

Media-timeline:

- `backend/src/routes/hydracamRoutes.ts`: scanned-session UI/API and ingestion
  triggers.
- `backend/src/routes/hydra.ts`: import, resume, manifest, timeline, and
  analysis routes.
- `backend/src/adapters/hydracam/HydraCamClient.ts`: legacy portal scraper.
- `backend/src/adapters/hydracam/HydraCamAdapter.ts`: event/File Registry/
  mirror ingestion path.
- `backend/src/services/hydraCamIngestionService.ts`: local registration and
  resume path.
- `backend/src/services/database.ts`: `events`, `event_media`, `event_devices`,
  `hydracam_mirror_*`, `hydracam_sessions`, and `ingested_sessions`.
- `services/file-server/src/fileRegistry.ts`: File Registry v2 dedupe by
  source/locator and filename.
- `docs/specs/EVENT_TIMELINE_HYDRACAM_SPEC.md`: event umbrella model.
- `/Users/jose/src/work/media-timeline/docs/superpowers/plans/2026-06-05-hydracam-bridge-integration.md`:
  existing implementation plan for the media-timeline bridge.

## Overlap Map

| Domain | HydraCam mobile | MoBo HydraCam | Media-timeline | Convergence |
| --- | --- | --- | --- | --- |
| Session identity | `CaptureSession.sessionId`, `sessionGuid` from API | `HydraCamSession.Id`, `Guid`, `SessionId` | `events.id`, `ingested_sessions.external_id`, `hydracam_mirror_sessions.session_guid` | Use `sessionGuid` as the stable cross-system key. Keep `hydracam-<numericId>` for legacy MoBo sessions; use `hydracam-<sessionGuid>` for new app-originated sessions unless a numeric source ID exists. |
| Media assets | Local files, `CapturedPhoto`, `CapturedVideo`, upload queue | `HydraCamPhoto`, `HydraCamVideo`, Azure `BlobPath` | File Registry v2, `event_media`, `event_assets`, `hydracam_mirror_assets` | Register every asset into File Registry, link it through `event_media`, and preserve the MoBo/app payload in mirror metadata. |
| Devices | `slaveDeviceId`, master/slave role runtime | `SlaveDeviceId` on photos/videos | `devices`, `event_devices`, `event_media.source_id` | Normalize to `hydracam:<deviceId>` and attach device metadata and timing offsets in media-timeline. |
| Timing | `captureDate`, video start/end, `receivedDate` | capture/received dates; current video metadata placeholders exist | `captured_at`, `received_at`, duration/fps/size/width/height, sync tables | Treat app capture timestamps as authoritative, then repair duration/fps from media probing when backend metadata is missing or placeholder. |
| Venue/user | App fetches courts, sports centers, user GUID by email | Courts, sports centers, HydraCam users, session users | event metadata, participants, ontology matching | Mirror MoBo venue/user data, but let media-timeline own event participants and sports ontology. |
| Storage | Local app documents/gallery files | Azure Blob `hydracam/<sessionGuid>/...` | File Registry locations, object storage/materialization | Historical assets can stay remote-only until materialized; new app uploads should land in media-timeline controlled storage with File Registry IDs. |
| APIs | Hardcoded Azure API base; `sessions/create`, `sessions/upload-media`, `sessions/end`, `courts`, `sportscenters` | `api/hydracam/CreateSession`, `UploadMedia`, `EndSession`, `courts`, `sportscenters`, `GetUserByEmail` | `/api/hydracam/*` scan/import and `/api/hydra/*` import/process/status | Add a bridge route family that accepts the app contract and maps it to event/File Registry writes before changing the app broadly. |
| Processing/timeline | No AI/timeline owner | No current AI/timeline owner | Timeline, File Registry, label-store, CV pipelines | Media-timeline is the owner. Do not add AI/timeline behavior to MoBo or the Flutter app. |

## What Should Be Merged

Merge these:

- New capture session creation into media-timeline event creation.
- New media upload into File Registry plus `event_media`.
- Device identity into media-timeline `devices` and `event_devices`.
- Historical MoBo sessions into media-timeline mirror tables and event umbrella.
- Timeline, AI, derived media, labels, and review workflows into media-timeline.
- App upload configuration into HydraCam mobile, so the backend target is not
  hardcoded.

Do not merge these:

- Do not move the Flutter app into media-timeline.
- Do not make MoBo the canonical owner for new AI/timeline work.
- Do not delete or bypass MoBo before historical sessions are mirrored and
  proofed.
- Do not start with a mobile rewrite. Prove the backend bridge first.
- Do not copy or preserve hardcoded MoBo/Auth0 secrets into new code. Rotate
  live credentials before production use.
- Do not rely on portal scraping for new captures. Keep scraping for legacy
  backfill only.

## Recommended Order

### Phase 0: Freeze The Facts

Goal: make the current contracts explicit before any cutover.

Actions:

- Capture example payloads from HydraCam mobile for create session, upload
  photo, upload video, end session, ready-to-transmit, courts, sports centers,
  and user lookup.
- Capture example MoBo responses for the same concepts, including the deployed
  route spelling that the current app actually reaches.
- Pick 3 to 5 legacy MoBo sessions with known media, including at least one
  multi-device session.
- In media-timeline, verify those sessions through `/api/hydracam/sessions`,
  `/api/hydra/:sessionId/manifest`, `/api/hydra/:sessionId/timeline`, File
  Registry resolution, and event umbrella.

Exit gate:

- A checked-in contract matrix names every app endpoint, MoBo endpoint,
  media-timeline target endpoint, request fields, response fields, auth mode,
  and storage outcome.

### Phase 1: Build The Media-timeline Bridge Foundation

Goal: make media-timeline capable of receiving direct app sessions without
touching the app first.

Actions:

- Execute the existing media-timeline plan starting with bridge schemas,
  identity helpers, upload-token auth, and bridge routes.
- Add stable IDs:
  - event ID
  - session GUID
  - normalized device ID
  - stable asset alias
  - File Registry file ID
- Add compatibility endpoints that accept the current app semantics:
  create session, upload media, end session, ready-to-transmit, status.
- Write through to `events`, `event_media`, `event_devices`,
  `hydracam_mirror_sessions`, `hydracam_mirror_assets`, and File Registry.
- Preserve MoBo-style payloads in mirror metadata for reconciliation.

Exit gate:

- Backend tests prove a photo and video upload create one event, two File
  Registry records, two `event_media` rows, event devices, and mirror rows.
- `git diff --check` and the media-timeline end-of-turn lint pass.

### Phase 2: Reconcile Legacy MoBo Sessions

Goal: keep history and current source links intact while moving canonical
review/processing to media-timeline.

Actions:

- Keep `HydraCamClient` portal scraping as a legacy adapter.
- Add or improve reconciliation reports by session GUID:
  - MoBo numeric session ID
  - session GUID
  - Azure blob URL
  - File Registry file ID
  - event ID
  - event_media row
  - mirror asset row
- Fix known metadata issues during import, especially placeholder video
  duration/fps/width/height.
- Identify duplicate filename collisions before re-registering historical
  assets, because File Registry v2 currently dedupes by filename after
  source/locator.

Exit gate:

- Selected legacy sessions show the same media count in MoBo, File Registry,
  event_media, the event umbrella, and timeline view.

### Phase 3: Cut The Flutter App To Bridge Compatibility Mode

Goal: make the smallest mobile change that routes new app uploads to
media-timeline while preserving capture reliability.

Actions:

- Make `HydraCamApiService` backend target configurable instead of hardcoded.
- Add bridge compatibility methods or a mode switch that maps app calls to
  media-timeline bridge endpoints.
- Keep `UploaderService` queue semantics unchanged: local files must remain
  durable until upload success is confirmed.
- Persist bridge metadata in `SessionManager` metadata:
  - `bridgeEventId`
  - `sessionGuid`
  - upload token metadata, without storing long-lived credentials
  - per-file File Registry ID after upload completion
- Keep a controlled legacy-MoBo fallback only as a setting or build-time
  configuration during migration.

Exit gate:

- Flutter tests cover target selection, bridge create-session response parsing,
  upload success/failure, and metadata persistence.
- No production Flutter code gains ad hoc `print()` logging.

### Phase 4: Prove On Real Devices

Goal: prove the merged product path, not only unit tests.

Actions:

- Run one physical-device app session through the media-timeline bridge:
  create session, capture one photo, capture one video, upload both, end
  session.
- Verify media-timeline:
  - event exists
  - File Registry resolves both assets
  - `event_media` has authoritative capture timestamps
  - event device exists
  - event timeline shows the video/photo
  - manifest/status route reports success
- Then run a two-device master/slave capture path and verify per-device source
  rows and timestamps.
- Store evidence under `logs/verification-runs/` in this repo for mobile proof
  and under the media-timeline evidence/log location for backend proof.

Exit gate:

- A run-specific evidence pack ties the mobile run to media-timeline event ID,
  File Registry IDs, timeline screenshots, and device logs.

### Phase 5: Production Upload Path

Goal: replace compatibility multipart uploads with a scalable large-video
path.

Actions:

- Add signed multipart/object upload start/sign/complete endpoints.
- Keep compatibility upload for small photos and migration fallback.
- On upload completion, write the same canonical records as Phase 1.
- Add upload resume/cancel/requeue behavior to the mobile app only after the
  bridge completion semantics are stable.

Exit gate:

- Large video upload succeeds without routing full file bytes through an
  unstable app/backend path, and File Registry/event_media are identical to the
  compatibility path from a consumer perspective.

### Phase 6: Unify Product UI And Deprecate MoBo Write Path

Goal: make media-timeline the operational UI for HydraCam events.

Actions:

- Update HydraCam Explorer so it clearly distinguishes:
  - legacy MoBo sessions
  - mirrored/imported sessions
  - new app-originated bridge sessions
  - processing/timeline readiness
- Move court/user/player/session review workflows into media-timeline only
  where they are needed for sports analysis.
- Leave MoBo as read-only historical admin until all required sessions are
  mirrored and verified.

Exit gate:

- New sessions no longer require MoBo to be writable.
- Legacy MoBo links remain discoverable for provenance.

## First Implementation Slice

The first slice should be media-timeline only:

1. Bridge request/response schemas.
2. Stable identity and alias helpers.
3. Upload token auth.
4. Compatibility create-session and upload-media endpoints.
5. Service write-through to File Registry, `event_media`, `event_devices`, and
   mirror tables.
6. A small route-level test proving a fake current-app upload appears in the
   event umbrella/timeline inputs.

Do not touch the Flutter app until this slice passes. That prevents a mobile
cutover from depending on unproven backend behavior.

## Open Decisions

- Should new app-originated event IDs be `hydracam-<sessionGuid>` or should
  media-timeline allocate a separate event ID while storing `sessionGuid` as a
  source ref?
- Should media-timeline copy legacy Azure blobs into controlled object storage
  immediately, or keep them remote-only until materialization is requested?
- Should courts/sports centers be mirrored from MoBo into media-timeline, or
  should the app eventually fetch venue data from a new media-timeline service?
- Which auth identity should issue app upload tokens: current Auth0 user,
  machine/device identity, or session-scoped bridge token created by a logged-in
  master?
- How much of MoBo's sub-session and drive-link model is still product-critical
  once media-timeline owns derived clips, timelines, and exports?

## Validation Policy

- Docs-only changes in this repo: `git diff --check`.
- Media-timeline bridge changes: focused Vitest tests, typecheck where
  relevant, Service Monitor health on `http://localhost:3009/health`, and
  `bash one-off-scripts/ops/end_of_turn_lint.sh`.
- Flutter app changes: `flutter analyze` plus focused `flutter test` targets;
  real-device evidence is required before claiming the bridge path works on
  hardware.
