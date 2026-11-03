# HydraCam Status and Roadmap

Last control-plane migration: 2026-06-05.
Last status refresh: 2026-08-26.

This document is scoped to `/Users/jose/src/work/hydracamv2`, the Flutter mobile
repo. Backend, web, Azure, and AI/product work is recorded only when it blocks
or informs the mobile app. Detailed dated status entries, device-matrix logs,
and superseded plans previously carried in this file have moved to
`docs/control/status-archive-2026.md` (verbatim, nothing dropped) to keep this
document current-focused and short.

## Current Mobile Status (summary)

As of 2026-08-26, mobile capture/role-switch/store-readiness fundamentals are
proven on the connected device fleet, and the last few weeks of work shifted
toward auth hardening and repo/tooling health rather than new capture proof:

- **Capture and role switching**: Android, iOS (simulator + physical
  iPhone/iPad), and macOS all have current-build capture and/or role-switch
  evidence; the iOS simulator remains launch/UI-only (no camera). Samsung S7
  edge has direct `standard1080p30` photo/video proof; higher S7 profiles
  remain unproven. See the archive's "Current Mobile Status" table for the
  full per-platform breakdown and evidence links.
- **Auth**: development auto-login works for automation devices;
  2026-08 work added an emulator auth smoke test covering dev-auto-login
  restore and process-death recovery. Full Android/iOS human-login smoke,
  logout, and account-switch proof remain open (see Release Blockers below).
- **Deploy/fleet infra**: `docs/control/hybrid-deploy-plan.md` was refreshed
  for the two-Mac local+remote build/deploy split, and device verification
  packs were recorded for the Android fleet (Wi-Fi provisioning, Xiaomi/POCO
  install unblock) through 2026-07-14.
- **Store distribution**: Android signed AAB is ready locally; iOS App Store
  IPA export is blocked on local Distribution signing; Google Play/App Store
  upload credentials are still unverified. No change since the last refresh.
- **Repo/tooling health**: a repo-and-tooling audit landed markdownlint +
  Flutter-quality CI, a change-scoped agent gate, scripts consolidation into a
  shared `hydracam_lib`, removal of the stale `docs/control/history/`
  snapshot archive (superseded by git history at `05b60544`), and a dedicated
  `master_server` unit test suite. This is process/quality work, not new
  device-capture proof.

For full per-date evidence narratives (device matrices, iOS/Android evidence
lists, and the detailed release-blocker history), see
`docs/control/status-archive-2026.md`.

## Current Goals

1. Make the app reliable on Android and iOS through repeatable real-device
   smoke tests. The prior iOS physical-device white-screen blocker is closed by
   newer iPhone/iPad evidence; do not reopen it without a fresh reproducible
   failure and logs.
2. Keep release/beta distribution paths ready for TestFlight plus Google Play
   internal, closed testing, and production-draft uploads, but do not claim
   production readiness without real device smoke tests.
3. Build a platform compatibility matrix across iOS, Android, macOS, Windows,
   Linux, and web as support expands.
4. Enable repeatable testing for master/slave session flow, capture, storage,
   upload, reconnect, low battery, and low storage behavior.

## Roadmap From Sheet Import

### Active Mobile Themes

- Session integrity: reconnect behavior, stale session state, joining existing
  sessions, and preventing media from crossing session boundaries.
- iOS reliability: client/server networking behavior, disconnects, navigation
  artifacts, signing/profile/release launch behavior, and regression coverage
  for the fixed iPad no-flash camera path.
- Upload and media handling: upload failure UI, cancel/requeue upload, upload
  progress/time estimates, version metadata, gallery import, and heavy video
  loading.
- Device/network awareness: show network identity, device IP/hardware/app
  version, disconnected clients, and multiple camera groups on the same LAN.
- Recording safety: critical battery autostop, storage autostop, foreground
  behavior, and synchronized time.
- Camera capture configuration: local per-device lens preference and target
  video profiles are now app settings; verify actual resolution/fps on iPhone
  12 Pro and Samsung S7/S10e before using them for production claims.
- Auto-record/unattended flow: devices start recording automatically when a
  slave connects to a master with an active session.
- Mobile authentication: restore valid Auth0 credentials on app start, persist
  refresh-capable credentials securely, end both local and browser/Auth0 sessions
  on logout, recover Android login after process death, and decide whether
  Android should use native Credential Manager/Sign in with Google for the
  account-picker experience users expect from other apps.
- Desktop/webcam support: desktop is monitoring/development-only for now; webcam
  capture is deferred (see the Desktop/Webcam Scope Decision in the archive).
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

## Standing Decisions (see archive for full text)

- **Android Device Support Floor** (decided 2026-06-06): active validation
  and distribution starts at Android API 24; the Lenovo Phab2/PB2-690M
  (Android 6.0/API 23) is deprecated and out of scope.
- **Desktop/Webcam Scope Decision** (decided 2026-06-06): Android and iOS are
  the primary capture targets; macOS/Windows/Linux/web stay
  development/diagnostics/monitoring/viewer-only, with desktop webcam capture
  deferred.

## Release Blockers (current)

- Android and iOS real-device smoke tests must pass on the exact release lane
  before any beta/production claim.
- Human-user login must survive app restart and Android process-death during
  browser authentication; logout/account switching must be validated before
  release claims depend on user identity. (2026-08 emulator auth smoke closed
  the dev-auto-login restore + process-death slice; human-login lanes remain
  open.)
- A two-device HydraCam flow must pass on the same local network or hotspot:
  discovery, slave connection, photo capture, video start/stop, local save,
  upload queue, and session end.
- iOS TestFlight upload remains blocked on local Distribution signing plus App
  Store Connect upload authentication (no local API key, `AuthKey_*.p8`, or
  `FASTLANE_SESSION`).
- Google Play upload remains blocked on `GOOGLE_PLAY_JSON_KEY` and unverified
  Play Console developer-account ownership.
- Camera lens/profile claims still need production-grade proof on remaining
  device/profile combinations (see archive for the current pass/fail matrix).
- Do not spend release-blocker time on Android 6.0/API 23 or older hardware
  (see Standing Decisions above).
- Docs and Linear issues must not imply backend/Azure work is complete unless
  it has current proof outside this mobile repo.

Full historical detail behind each of the above (dates, evidence-pack paths,
SHA-256 artifact hashes, and superseded blockers) lives in
`docs/control/status-archive-2026.md`.

## Pointers

- `docs/control/README.md`: control-plane index and document map.
- `docs/control/status-archive-2026.md`: full historical status log, device
  matrices, and evidence narratives moved out of this file on 2026-08-26.
- `docs/control/backlog-import.md`: imported backlog staging (frozen
  2026-06-25; canonical backlog is moving to Linear per `AGENTS.md`).
- `docs/control/evidence-first-loop.md`: required evidence-pack contract for
  hardware/emulator-backed verification work.
- `docs/control/hybrid-deploy-plan.md`: two-Mac local+remote build/deploy plan.
- `docs/control/android-auth-sign-in-decision.md`: Android login decision
  record (Auth0 Universal Login retained; native Credential Manager deferred).
- `AGENTS.md`: canonical agent control plane and validation policy.
