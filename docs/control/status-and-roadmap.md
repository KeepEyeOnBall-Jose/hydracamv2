# HydraCam Status and Roadmap

Last control-plane migration: 2026-06-05.

This document is scoped to `/Users/jose/src/work/hydracamv2`, the Flutter mobile
repo. Backend, web, Azure, and AI/product work is recorded only when it blocks
or informs the mobile app.

## Current Mobile Status

| Area | Status | Notes |
| --- | --- | --- |
| iOS simulator | Working | Existing repo guidance says simulator runs. Re-verify before relying on this for release readiness. |
| iOS physical device | Blocked | App installs and launches but shows a white screen. This remains a release blocker. |
| Android | In development | Existing automation and distribution scaffolding exist, but physical-device validation still needs current proof. |
| Desktop and web | macOS controller debug path working; capture deferred | macOS debug `.app` builds and launches for controller/monitoring use with a mock local camera. Windows, Linux, web, and real desktop webcam capture remain future support. |
| Multi-device capture | Core architecture present | Master/slave WebSocket flow exists; current confidence should come from fresh multi-device validation. |
| Store distribution | Prepared, not submitted | Distribution runbook and scaffolding exist; real submission depends on signing, credentials, privacy review, and device smoke tests. |

## Current Goals

1. Make the app reliable on Android and iOS, with the iOS physical-device white
   screen treated as the highest release blocker.
2. Keep release/beta distribution paths ready for TestFlight and Google Play
   internal testing, but do not claim production readiness without real device
   smoke tests.
3. Build a platform compatibility matrix across iOS, Android, macOS, Windows,
   Linux, and web as support expands.
4. Enable repeatable testing for master/slave session flow, capture, storage,
   upload, reconnect, low battery, and low storage behavior.

## Roadmap From Sheet Import

### Active Mobile Themes

- Session integrity: reconnect behavior, stale session state, joining existing
  sessions, and preventing media from crossing session boundaries.
- iOS reliability: white screen, client/server networking behavior, disconnects,
  iPad camera save failures, and navigation artifacts.
- Upload and media handling: upload failure UI, cancel/requeue upload, upload
  progress/time estimates, version metadata, gallery import, and heavy video
  loading.
- Device/network awareness: show network identity, device IP/hardware/app
  version, disconnected clients, and multiple camera groups on the same LAN.
- Recording safety: critical battery autostop, storage autostop, foreground
  behavior, and synchronized time.
- Autograbado/unattended flow: devices start recording automatically when a
  slave connects to a master with an active session.
- Desktop/webcam support: desktop is monitoring/development-only for now; webcam
  capture is deferred by the scope decision below.
- User/player assignment: attach players/users to sessions and support mid
  session player additions.

### External Backend/Web Dependencies

- Material retrieval endpoint and slow heavy-video gallery behavior.
- Backend upload metadata fields and duration fixes.
- SignalR hub, Azure queue, delivery package, queue processors, and live
  monitoring.
- QR/user request flow for unattended court activation.
- GDPR document hosting and consent gating if implemented outside the mobile
  app.

### Future Product Ideas

These came from `SYSTEM FEATURES` and should stay roadmap-only until explicitly
pulled into active mobile work:

- AI rally segmentation, shot classification, ball/wall contact inference, heat
  maps, player body position, errors/winners location, and 3D reconstruction.
- Video referee features: live human review, AI decisioning, democratic review,
  and instant replay.
- Games and fan-facing experiences: guess-the-next-shot, referee game, loud
  calls, and score/VAR overlays.
- External refereeing/annotation APIs, user annotation, strategy suggestions,
  ball speed, step/distance counters, and padel/squash edge-case rulings.

## Release Blockers

- iOS physical-device white screen must be fixed before iOS production
  submission.
- Store privacy answers must be reviewed against current code and backend
  behavior before submission.
- Android and iOS real-device smoke tests must pass.
- A two-device HydraCam flow must pass on the same local network or hotspot:
  discovery, slave connection, photo capture, video start/stop, local save,
  upload queue, and session end.
- Docs and Linear issues must not imply backend/Azure work is complete unless it
  has current proof outside this mobile repo.

## Desktop/Webcam Scope Decision

Decision date: 2026-06-06.

This completes the imported backlog decision task for `JAVI IMMEDIATE BACKLOG`
rows 76, 83, and 103.

| Platform | Current scope | Capture support |
| --- | --- | --- |
| Android | Primary mobile target for master/slave capture and validation. | In scope. |
| iOS | Primary mobile target after physical-device white-screen blocker is fixed. | In scope. |
| macOS/Windows/Linux | Development, diagnostics, monitoring, and possible viewer/control workflows only. | Deferred. |
| Web | Future viewer/control or portal surface only. | Deferred. |

Desktop/webcam capture is not an active implementation target in this mobile
repo. Reopening that scope would require a separate design for camera APIs,
file/gallery persistence, permission behavior, packaging, and cross-platform
test coverage. Until then, do not create Linear issues for generic "use webcam"
or "Windows version" rows unless a concrete non-capture monitoring/control
workflow is requested.

2026-06-07 update: macOS native controller support is now enabled for debug
builds without implementing desktop webcam capture. The app skips unsupported
`permission_handler` startup calls on macOS, defaults local master recording off
on macOS unless the user explicitly enables it, signs debug/release macOS
targets with local-network/media/location entitlements, and uses a mock local
camera path so controller flows can run while real desktop capture remains
deferred.
