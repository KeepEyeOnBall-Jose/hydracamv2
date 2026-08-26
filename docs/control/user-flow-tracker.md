# HydraCam User Flow Tracker

Last reviewed: 2026-06-18 (content dated 2026-06-18).
Last derived: 2026-06-11.

This is the repo-local tracker for product and validation user flows. It is
derived from `docs/control/architecture-and-testing.md`,
`docs/control/status-and-roadmap.md`, `docs/control/backlog-import.md`,
`docs/control/requirements.md`, `docs/control/device-relationship-fsm.md`, the
automation scenario manifests, and current evidence packs under
`logs/verification-runs/`.

Use this file to keep user journeys, test coverage, and proof gaps in one
place. Do not treat a flow as release-ready unless the named evidence gate has
passed with the required evidence tier from `docs/control/evidence-first-loop.md`.
For the corresponding finite-state-machine diagrams, see
`docs/control/user-flow-fsm-diagrams.md`.

## Status Legend

| Status | Meaning |
| --- | --- |
| `proven` | The current repo has a matching run-specific evidence pack for the flow. |
| `partial` | Code or local tests exist, but the real user/device flow is incomplete or not recently proven. |
| `blocked` | The latest evidence records a concrete environment, device, credential, or product-contract blocker. |
| `future` | The flow is product-valid but depends on backend/web/Azure/media-timeline work not owned entirely by this repo. |

## Guardrails

- Keep role-only proof separate from capture proof. Runtime role switching proves
  the fleet can rotate master authority; it does not prove photo/video capture
  after every rotation.
- Keep independent local capture proof separate from master/slave broadcast
  proof. The parallel device matrix intentionally launched devices as local
  masters.
- Keep software-level clock-sync proof separate from physical two-camera
  alignment proof.
- Keep upload UI proof separate from live backend upload proof.
- Keep Auth0 unit coverage separate from Android/iOS account recovery smoke.
- Every device-facing flow needs a run-specific evidence pack with screenshots,
  video, and device logs before being called done.

## Flow Index

| ID | Flow | User intent | Status | Best current evidence | Open release gap |
| --- | --- | --- | --- | --- | --- |
| UF-01 | First run, login, and account recovery | A user can open the app, authenticate, recover the same account after restart, and log out cleanly. | partial | `logs/verification-runs/20260609-0426-auth0-mobile-platform-boundary-cleanup/`, `logs/verification-runs/20260609-0432-login-desktop-auth0-message/` | Android and iOS smoke for login, process-death restore, account switching, and logout. |
| UF-02 | Camera setup, leveling, lens, and profile selection | An operator can place each camera, choose the intended lens/profile, and see usable preview/leveling guidance. | partial | `logs/verification-runs/20260608-1533-camera-leveling-device-continuation/`, `logs/verification-runs/20260609-1405-s7-higher-resolution-compat/` | Physical iPhone setup proof, iOS saved-video metadata, and wider profile matrix closure. |
| UF-03 | Single-device capture smoke | One device can start a session, take a photo, record video, save media, and stop cleanly. | proven on selected devices | `automation_scenarios/single_device_capture_profile.json`, `logs/verification-runs/20260609-0021-ipad-physical-release-profile-smoke/`, `logs/verification-runs/20260609-1405-s7-higher-resolution-compat/` | Repeat on release-lane iPhone, iPad, and at least two supported Android devices before beta claims. |
| UF-04 | Attended master/slave capture session | An operator starts one master, slaves connect, one session captures photo/video across devices, and devices upload their own media. | partial | `automation_scenarios/quad_smoke_with_video_fixed.json`, `logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/summary.md`, `logs/verification-runs/20260609-0930-all-hardware-ios-android-update-role-test/summary.md` | A true repeated two-device iOS/Android master/slave capture and upload pack; current strongest broad proof is role-switch, not capture. |
| UF-05 | Runtime master handoff and rotating master | Any selected device can become master without relaunching, while the others become slaves and connect. | proven for selected sets; blocked for latest eight-target run | `logs/verification-runs/20260608-latest-cache-shortest-default-staged-five-hot/summary.json`, `logs/verification-runs/20260609-0930-all-hardware-ios-android-update-role-test/summary.md`, `logs/verification-runs/20260611-0237-eight-target-random-master-role-switch/summary.md` | Resolve current ADB timeouts and subnet split before claiming eight-target random-master coverage. |
| UF-06 | Upload queue, progress, failure, cancel, and retry | A user can understand upload progress, recover failed uploads, cancel queued/current uploads, and send upload commands to slaves. | partial | `logs/verification-runs/20260608-1933-inflight-upload-cancel-control/`, `logs/verification-runs/20260609-0245-uploader-manual-upload-future-cleanup/` | Real-device plus live-backend upload smoke and server-side failure/response confirmation. |
| UF-07 | Session reconnect and master-loss recovery | A slave reconnects without losing session/media; master disappearance has a clear recovery policy. | partial | `docs/control/device-relationship-fsm.md`, `logs/verification-runs/20260609-0353-master-screen-dispose-lifecycle-contract-cleanup/`, `logs/verification-runs/20260609-0517-automation-local-only-guard-cleanup/` | Real master/slave reconnect reproduction, cross-device metadata comparison, and explicit production master-loss authority policy. |
| UF-08 | Clock-sync and synchronized capture | Two physical devices capture media with persisted sync metadata and measured alignment error under target. | partial | `logs/verification-runs/20260610-time-sync-software-evidence/`, `docs/control/time-sync-two-device-runbook.md`, `docs/control/time-sync-ground-truth-protocol.md` | Physical two-device capture plus clap/flash ground-truth analysis. |
| UF-09 | Auto-record and unattended court operation | Venue devices can remain ready, join an active session, start recording automatically, and stop safely. | partial | `logs/verification-runs/20260608-1848-autograbado-session-autostart/`, `logs/verification-runs/20260608-2045-slave-recording-safe-stop-control/` | Real-device unattended recording proof, managed-fleet authority model, and backend/QR activation contract. |
| UF-10 | Gallery and old-media session attachment | A user can browse historical media, find likely matching sessions, and attach media without corrupting active metadata. | partial | `logs/verification-runs/20260608-1953-gallery-historical-session-candidate-source/`, `logs/verification-runs/20260609-0506-session-directory-identifier-scan-cleanup/` | Real gallery attachment smoke and broader GUID/controller audit if still needed. |
| UF-11 | Network/device identity and diagnostics | The operator can see which devices, networks, and app builds are active and identify a physical slave. | partial | `logs/verification-runs/20260608-2030-master-device-list-summary-sort/`, `logs/verification-runs/20260609-0445-slave-identify-visible-frame/` | Real multi-device diagnostic proof and any future hardware flash/frame identification behavior. |
| UF-12 | Store beta install, privacy, support, and deletion links | A tester can install a store-ready build and reach privacy/support/account-deletion surfaces. | blocked | `logs/verification-runs/20260609-store-readiness-static-build/summary.md`, `docs/control/store-privacy-and-metadata.md` | Public HTTPS URLs, upload credentials, current IPA export/signing, and release-lane hardware smoke. |
| UF-13 | Mobile to media-timeline bridge and retrieval | New mobile captures land in the canonical event/media/timeline backend for review and AI processing. | future | `docs/control/hydracam-mobo-media-timeline-merge-plan.md` | Backend bridge contract, payload examples, mobile endpoint configurability, and end-to-end bridge proof. |
| UF-14 | Slave preview and live monitoring | The master can monitor slave readiness and preview state during setup/capture. | future | `logs/verification-runs/20260608-2105-master-slave-preview-missing-state/`, `docs/control/requirements.md` FR-045/FR-046 | Preview transport design, bandwidth limits, master UI behavior, and real multi-device preview evidence. |

## Flow Details

### UF-01 First Run, Login, And Account Recovery

Happy path:

1. User opens HydraCam.
2. User signs in through the supported mobile Auth0 path.
3. The app maps the Auth0 identity to a HydraCam user GUID.
4. User force-closes and reopens the app.
5. Stored credentials restore or refresh without an unnecessary browser prompt.
6. Logout clears app state and Auth0/browser session state enough to prevent
   accidental reuse of the previous account.

Current proof is mostly local service and widget coverage. The release gate is
an Android and iOS run that captures the full login, restore, account-switch,
and logout behavior with device logs.

### UF-02 Camera Setup, Leveling, Lens, And Profile Selection

Happy path:

1. Operator opens camera setup on each device.
2. The app renders local preview.
3. Operator chooses perspective, lens, and video profile.
4. The leveling guidance warns without blocking capture.
5. The selected lens/profile survives navigation and is used by later capture.

Current evidence proves the setup preview path on reachable devices and the S7
1080p compatibility fix. Remaining gaps are iPhone setup proof and iOS native
metadata limits.

### UF-03 Single-Device Capture Smoke

Happy path:

1. Device applies capture settings.
2. Device starts a local or backend session.
3. Device takes a photo.
4. Device starts and stops video recording.
5. Photo, video, metadata, and upload queue state are inspectable.
6. Device ends the session cleanly.

This is the cleanest smoke flow for isolating camera/plugin failures before
adding master/slave networking.

### UF-04 Attended Master/Slave Capture Session

Happy path:

1. Operator starts a master on the court network or hotspot.
2. Slaves discover or are assigned the master and connect over WebSocket.
3. Operator starts a backend session from the master.
4. Master sends photo and video commands.
5. Each device captures locally and queues its own upload.
6. Operator stops recording and ends the session.
7. Uploaded media and local metadata match the same session GUID.

This is the core product flow. Current broad device evidence is strong around
independent capture and role switching, but the release gate is still a true
two-device master/slave capture and upload evidence pack.

### UF-05 Runtime Master Handoff And Rotating Master

Happy path:

1. Selected devices are warm on identity-matched automation bridges.
2. Runner promotes one device to master.
3. Runner points every other selected device at the promoted master as slave.
4. Promoted master sees the expected connected clients.
5. Rotation repeats with each selected device becoming master.

Current five- and six-device role-switch evidence is good. The latest local
eight-target random-master pack is blocked by ADB command timeouts on one S10e
and by selected devices split across routable subnets.

### UF-06 Upload Queue, Progress, Failure, Cancel, And Retry

Happy path:

1. Captured media enters the upload queue.
2. User sees progress, bytes, and estimated time.
3. Failed media shows a distinct failed state.
4. User can retry pending/failed uploads.
5. User can cancel pending or active uploads.
6. Slaves can receive a start-upload command and expose uploader info.

Most mobile UI/service slices are implemented and tested. Production closure
requires a live backend upload smoke and response-shape confirmation.

### UF-07 Session Reconnect And Master-Loss Recovery

Happy path:

1. Slave joins an active master session and records session GUID.
2. Master or slave temporarily disconnects.
3. Reconnection preserves local media and uploader state for the same session.
4. Conflicting session/master identity is surfaced instead of silently merged.
5. If the master disappears, devices follow an explicit authority policy.

The FSM document shows the current gap: screen-level rediscovery exists, but
there is not yet a production-safe election/lease/master-loss contract.

### UF-08 Clock-Sync And Synchronized Capture

Happy path:

1. Slave calibrates against master time.
2. Slave shows green sync status before capture.
3. Master triggers photo/video capture.
4. Captured media persists `syncMetadata` in session metadata and sidecar JSON.
5. A shared clap/flash event is measured across clips.
6. Analysis reports alignment error plus uncertainty under the target.

Software evidence proves calibration and persistence. The physical two-camera
ground-truth run remains pending.

### UF-09 Auto-Record And Unattended Court Operation

Happy path:

1. Venue devices are installed, powered, foregrounded, and network-ready.
2. User requests recording through a QR/web/backend flow.
3. Backend or master authorizes the session.
4. Slaves auto-start only when a clear active-session condition is present.
5. Recording can be stopped safely by operator or policy.
6. Media uploads without relying on the user handling each device.

Current repo proof covers the setting, mock auto-start, and safe stop UI. The
full unattended flow is cross-project and needs a backend activation contract.

### UF-10 Gallery And Old-Media Session Attachment

Happy path:

1. User opens historical/gallery import.
2. User can browse with or without filters.
3. App suggests sessions near the media timestamps.
4. User attaches selected media.
5. Active session metadata remains unchanged unless explicitly edited.
6. Restored historical sessions requeue media exactly once.

Current coverage is mostly local model/widget/service proof. The release gate
is a real gallery attachment smoke on a device.

### UF-11 Network/Device Identity And Diagnostics

Happy path:

1. Master shows known, live, and disconnected devices.
2. Operator can identify the physical device, app version, network/IP, and
   session status.
3. Disconnected devices remain visible as stale history instead of vanishing.
4. Operator can trigger a visible identify frame on a selected slave.

Current UI/service proof is useful. The remaining gap is a real multi-device
diagnostic run that proves this helps during actual court setup.

### UF-12 Store Beta Install, Privacy, Support, And Deletion Links

Happy path:

1. Owner builds current Android/iOS store artifacts with final public URLs.
2. Store preflight validates identity, privacy manifest, app icons, metadata,
   signing, and sidecar hashes.
3. Tester installs the build from TestFlight or Play testing.
4. Login screen exposes privacy, support, and account deletion routes.
5. Release-lane hardware smoke passes before external claims.

The Android artifact path is much closer than iOS. Current blockers include
public URLs, upload credentials, and current IPA export/signing.

### UF-13 Mobile To Media-Timeline Bridge And Retrieval

Happy path:

1. Mobile app creates a capture session through a bridge-compatible API.
2. Media uploads create event/media/device rows and File Registry entries.
3. App stores bridge identifiers next to device-stored service-session metadata.
4. Users retrieve raw and processed materials through media-timeline surfaces.
5. AI/timeline review operates on the canonical event/media model.

This is intentionally future/cross-project. The mobile repo should preserve
durable local capture and upload queue semantics while the backend bridge is
proved first.

### UF-14 Slave Preview And Live Monitoring

Happy path:

1. Slave readiness is visible to the master.
2. Master shows a clear preview state for each slave.
3. Missing preview transport is explicit and non-misleading.
4. Once transport exists, bandwidth and latency are bounded enough for setup.

The current app exposes missing-preview state truthfully. Actual preview
transport remains a design and implementation task.

## Suggested Validation Order

1. Close UF-04 with a two-device master/slave capture and upload pack, because
   it is the core attended product flow and prevents role-switch proof from
   being overread.
2. Close UF-08 with the physical clock-sync ground-truth run if synchronized
   sports capture is the next product claim.
3. Close UF-01 and UF-12 before any external beta, because login recovery,
   public URLs, signing, and store credentials are release gates.
4. Re-run UF-05 only after the current subnet/ADB blockers are resolved, then
   decide whether eight-target random-master coverage matters for the current
   milestone.
