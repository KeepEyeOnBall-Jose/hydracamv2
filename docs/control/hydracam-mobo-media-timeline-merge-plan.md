# HydraCam, MoBo, And Media Timeline Merge Plan

Last reviewed: 2026-06-12.

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

For diagrams of the API calls, endpoint families, data stores, and cutover
boundaries, see `cross-project-api-data-map.md`.
For the corresponding user-flow and cross-system FSMs, see
`user-flow-fsm-diagrams.md`.

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
- `lib/services/session_manager.dart`: device-stored service-session metadata,
  media tracking, and upload queue handoff.
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

## Recovered Attempt And Chat Ledger

This section recovers the previous Codex chats, repo efforts, and durable
artifacts found while trying to connect HydraCam mobile, MoBo webservice, and
media-timeline.

| Date | Chat / rollout | What was recovered | Durable result |
| --- | --- | --- | --- |
| 2026-06-03 | `019e8d51-8f19-7b61-bcec-0927ff7d877a` | Found HydraCam as an active media-timeline workstream, not only a separate app. Checked Service Monitor, active routes, UI, and live local APIs. | media-timeline already exposed `/api/hydracam/*`, `/api/hydra/*`, `HydraCamExplorer`, and 113 indexed sessions, but only 8 had local event-media rows at that time. |
| 2026-06-03 | `019e8d52-ef73-70e3-8cd8-f87e2ce15723` | Recovered the original upstream HydraCam links rather than deployed mirror links. | Source pages use `https://hydracam.azurewebsites.net/HydraCam/Details/<sessionId>` and media files live under `https://keob2.blob.core.windows.net/hydracam/<session-guid>/...`; the bounded check found all 113 indexed sessions live by detail-page plus first-blob probe. |
| 2026-06-04 | `019e92e2-57dc-7f70-ac96-52092cfd903d` | Located the actual project roots and separated active repos from obsolete copies. | Active roots are `/Users/jose/src/work/hydracamv2` and `/Users/jose/src/work/mobo`; `allKEOB/projects/hydracam-mobile` and `allKEOB/projects/mobo` point to them. Obsolete mobile copies were removed only after ancestry/content checks. |
| 2026-06-05 | `019e96df-ee6a-7e62-bf19-96f4af48a0d4` | Explored the `Alicia video-store API` concept against the HydraCam/KEOB workspace. | Confirmed the concept is a retrieval/video-store API (`POST /streams`, `POST /downloads`, `GET /downloads/{downloadId}`), not a mobile recording feature. Initial MoBo/KEOB fit was blocked on whether `from`/`to` means exact clipping, existing-file overlap, or hybrid. |
| 2026-06-05 | `019e96dd-d358-7860-bdaa-9b45d52eb699` | Mapped the Alicia concept into media-timeline and prepared implementation. | Saved `/Users/jose/src/work/media-timeline/docs/superpowers/plans/2026-06-05-video-store-api.md` and created branch `codex/video-store-api`; implementation workers were not completed in that chat. As of 2026-06-12, no `backend/src/**/videoStore*.ts` files are present. |
| 2026-06-05 | `019e97d2-ef0a-7210-bd77-5919f5bd4298` | Planned HydraCam app plus MoBo webservice ingestion into media-timeline. | Saved `/Users/jose/src/work/media-timeline/docs/superpowers/plans/2026-06-05-hydracam-bridge-integration.md`; chose a hybrid bridge, not a repo merge. The plan identified hardcoded mobile credentials/config as a rotation and replacement requirement. |
| 2026-06-05 | `019e97d1-f7e2-7a22-b746-9b8749a1a01a` | Folded the bridge plan into the large media-timeline branch snapshot. | The bridge plan was included in the unified branch snapshot after Service Monitor and end-of-turn lint checks. |
| 2026-06-05 | `019e97dc-ea8c-77c2-b6c1-cddf896d5d12` | Explored streaming, progressive ingest, and near-live AI options across HydraCam and media-timeline. | Kept media-timeline as backend owner for new capture/streaming control. Concluded the current Flutter app is file-recording-centric; near-live AI needs either a sampled frame/proxy side-channel, WebRTC/LiveKit, or a native segmented recorder. |
| 2026-06-09 | `019eaa8b-faab-70f1-b707-e01d3843c661` | Ran a concrete end-to-end ingest using the existing phone-intake / HydraCam bridge workflow for Airport Squash Court 4. | Created legacy session `482` with GUID `3c49d227-fbfb-4b59-8087-29dbe2484de1`, ingested 12 videos into media-timeline, and processed 72/72 required stages. The legacy HydraCam page existed but its Videos table stayed empty, so media-timeline was the complete processed record. |

## Current Recovery Snapshot

As of 2026-06-12, the actual source trees show this state:

- HydraCam mobile remains on the legacy Azure app-service API path. The current
  app code still has `lib/services/hydracam_api_service.dart` pointing at
  `https://hydracam.azurewebsites.net/api`, and repo flow `UF-13` is still
  marked `future` in `docs/control/user-flow-tracker.md`.
- MoBo remains the legacy webservice. `/Users/jose/src/work/mobo` is currently
  detached at `HEAD`, has no media-timeline bridge or video-store references,
  and still exposes the legacy `api/hydracam` controller methods such as
  `CreateSession`, `UploadMedia`, `EndSession`, `device/ReadyToTransmit`,
  `courts`, and `sportscenters`.
- media-timeline is the only repo with bridge implementation code. On branch
  `codex/video-store-api`, commits `735367d65`, `5b3854fb1`, and merge commit
  `f41f99338` added portable bridge storage, bridge service/routes/tests, and
  route mounting under `/api/hydracam-bridge`.
- media-timeline is still not clean. Bridge-related uncommitted state includes
  a modified `backend/src/services/hydraCamBridgeService.ts` plus untracked
  `frontend/src/services/hydraCamBridgeApi.ts`,
  `frontend/src/services/hydraCamBridgeApi.test.ts`, and
  `e2e/hydracam-bridge-upload.spec.ts`.
- The recovered video-store API is still a saved plan, not source code. The
  plan remains at
  `/Users/jose/src/work/media-timeline/docs/superpowers/plans/2026-06-05-video-store-api.md`.

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

### Debug Session Cleanup Contract

Debug builds create service sessions whose requested `SessionId` starts with
`debug-<platform>-<utc timestamp>`. The mobile app stores the service GUID,
display session id, and numeric MoBo id when the create response includes one.
Uploaded debug media is deleted from the device after successful upload even
when the normal release setting keeps local files.

The service cleanup lane is
`POST /api/sessions/debug/delete?sessionGuid=<guid>&id=<numericId>`.
Mobile clients record cleanup candidates and can drain that registry through
`DebugSessionCleanupService`. Until MoBo or media-timeline exposes the endpoint,
live deletion is an integration contract rather than proven service behavior.

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

Progress note as of 2026-06-12: this first slice is partially implemented in
media-timeline, not in HydraCam mobile. The bridge has backend service, storage,
identity, auth, route, and reference-doc coverage, but the current branch still
has uncommitted/untracked bridge work and the Flutter app has not been cut over.

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
