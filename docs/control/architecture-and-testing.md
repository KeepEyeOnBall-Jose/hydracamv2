# HydraCam Architecture and Testing

Source: deprecated Google Sheet `HydraCam Dev Process`, read 2026-06-05, plus
current repo control-plane context.

## Architecture Summary

HydraCam is a Flutter mobile app for synchronized multi-device camera capture.
One master device coordinates one or more slave devices over a local
network/hotspot. The sheet also described a future backend-led unattended mode
with Azure-hosted services.

### Main Components

| Component | Description | Technologies / services | Scope |
| --- | --- | --- | --- |
| Flutter app | Mobile app used by master and slave devices. Master controls capture, slaves execute commands, devices save and upload media. | Flutter, camera plugins, WebSocket client/server | mobile |
| Local master/slave control | Master advertises/accepts slaves; slaves discover/connect, send heartbeats, and receive commands. | WebSocket, local network/hotspot | mobile |
| Backend API / web app | Manages APIs, authentication, business logic, and session/material access. | ASP.NET Core MVC, Entity Framework Core | external-backend |
| Azure SignalR Service | Future real-time backend-to-device communication for unattended mode. | Azure SignalR Service | external-backend / cross-project |
| Azure Blob Storage | Stores captured media files. | Azure Blob Storage | external-backend |
| Database | Stores persistent user, session, recording metadata, and device configuration. | Azure SQL Database or Cosmos DB | external-backend |
| Queues and processors | Future processing pipeline for uploaded materials and AI/media tasks. | Azure Queues, containers/nodes | external-backend |
| Auth0 | Handles users, logins, and device/API auth surfaces. | Auth0 Web App, API, M2M app | cross-project |

## Operational Modes

### Attended Mode

User-owned devices are manually arranged for a recording session.

1. User launches the Flutter app as master.
2. Additional devices launch as slaves and connect to the master.
3. User starts a recording session from the master UI.
4. Master sends photo/video commands to slaves.
5. Devices store media locally and upload through the configured API path.
6. User ends the session and validates uploads/materials.

### Unattended Mode

Venue-owned devices are pre-installed on courts and activated by a user request
or QR flow. This is mostly future/cross-project work.

1. Master and slave devices remain fixed on a court.
2. User arrives and requests recording, likely through QR/web flow.
3. Backend validates and starts a session.
4. Backend or master notifies devices to start recording.
5. Devices record automatically and upload media.
6. User retrieves processed or raw materials through app or web surfaces.

## Auth0 Components

| Component | Application type | Usage |
| --- | --- | --- |
| `HydraCamWeb` | Regular Web Application | User login and session management. |
| `HydraCamAPI` | API | Protected endpoints for web and device calls. |
| `HydraCamDevices` | Machine-to-Machine Application | Device/API access without an interactive human user. |

Current mobile human login uses `flutter_appauth` to launch Auth0 Universal
Login in a browser or Chrome Custom Tab. That is different from Android's native
Credential Manager/account-picker UI. Treat startup credential restore,
refresh-token storage, logout/end-session behavior, Android process-death
recovery, and Android-native account selection as incomplete until the backlog
auth tasks are implemented and verified.

## Diagram Source

The deprecated sheet linked an architecture diagram:

<https://app.diagrams.net/#G13ivH6JrmjknLkT9zq6gBAuy4rakvh2Cl#%7B%22pageId%22%3A%22O5XeV3fmeWpZQj4B0OHx%22%7D>

If this diagram is still authoritative, export it into repo-friendly
documentation or reference it from an issue. Do not rely on the spreadsheet tab
as the only pointer.

## Test Strategy

Use the sheet's `Testing table` as a seed list and the repo's multi-device test
plan as the execution surface.

### Mobile Test Priorities

| Candidate | Source IDs | Expected proof |
| --- | --- | --- |
| Auth0 login flow | T-001 | Login succeeds; startup restore, Android process-death recovery, invalid/expired token paths, logout, and account switching are handled cleanly. |
| Mobile record start/stop | T-017 | Recording starts/stops, file is saved locally, low storage/battery paths do not corrupt state. |
| Mobile upload path | T-018, T-016 | Upload succeeds for valid files, invalid files produce friendly errors, retries do not duplicate media. |
| Time synchronization | T-019 | Devices maintain capture scheduling within the chosen accuracy target. |
| Upload estimate | T-020 | Estimate reflects observed bytes/time and handles network fluctuation. |
| Readiness and preview | T-021, T-022 | Slave readiness and previews appear in real time when feature is implemented. |
| Multi-device smoke | Repo test plan | Master discovery, slave connection, photo, video, local save, upload queue, and session end pass on at least two devices. |

### Backend/Web Tests

The following sheet tests are backend/web-owned unless the mobile repo provides a
mock/integration harness for them:

- T-002 database and storage connections.
- T-003/T-014 API session retrieval.
- T-004 Docker deployment.
- T-005 queue processing.
- T-006 through T-013 SignalR, QR, and web session initialization.
- T-015 sports center/court CRUD.
- T-023 delivery package notification.

### Acceptance for New Mobile Work

- Create and validate a run-specific evidence pack using
  `docs/control/evidence-first-loop.md` and `scripts/evidence_pack.py` before
  marking device-facing work complete.
- For UI, release, session, network, capture, battery, storage, or upload work,
  evidence must include screenshots/video/device logs from real hardware,
  emulator, simulator, or the multi-device emulator cluster as appropriate.
- Add or update focused tests when changing services, singleton state,
  WebSocket behavior, session state, uploader behavior, or app startup.
- For docs-only control-plane changes, run `git diff --check`.
- When device/SDK/signing/backend credentials are unavailable, record the
  skipped command and blocker instead of treating the check as passed.
