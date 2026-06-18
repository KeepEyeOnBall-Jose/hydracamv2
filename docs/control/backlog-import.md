# Linear Backlog Import Queue

Source: deprecated Google Sheet `HydraCam Dev Process`, read 2026-06-05.

Live Linear issue creation is gated until the Linear workspace, team, project,
labels, and connector tools are available. This file is the deterministic import
queue.

Default issue schema:

- Title: concise issue title.
- Body: source sheet/row, original text, scope, and acceptance checks.
- Labels: `hydracam`, `mobile`, plus component labels such as `ios`, `android`,
  `upload`, `session`, `sync`, `testing`, `external-backend`.
- Priority: preserve sheet priority where present. Without a sheet priority,
  data-loss, app-launch, recording, and session-reset bugs are high.

## Priority Issue Candidates

### 0. ASAP: Validate camera lens and video profile settings on iPhone/Samsung

- Source: 2026-06-07 camera settings implementation plan:
  `docs/superpowers/plans/2026-06-07-camera-lens-video-settings.md`.
- Labels: `hydracam`, `mobile`, `camera`, `ios`, `android`,
  `release-blocker`.
- Priority: High.
- Body: HydraCam now has local camera lens and target video profile settings.
  Each device chooses its own lens/profile before executing existing
  master/slave capture commands. iPhone devices should expose ultra-wide/wide
  and telephoto when hardware supports them; Android devices may expose opaque
  CameraX IDs, enriched with Camera2 focal-length metadata when available.
- Acceptance checks: iPhone 12 Pro records with Ultra Wide (0.5x) at
  `sport1080p60` and `detail4k30`; Samsung Galaxy S7 records rear wide at
  `sport1080p60` and `detail4k30`; S10e or newer Samsung repeats at least one
  profile; saved-video metadata logs include actual width/height/fps or a clear
  unavailable message; changing profile does not reset the selected lens.
- 2026-06-07 verification note:
  `logs/verification-runs/20260607-camera-settings-device-matrix/summary.md`
  records the current matrix. Physical iPad passed `autoBack` +
  `standard1080p30`; Samsung S10e partially passed `autoBack` +
  `standard1080p30` with `1920x1080, unknown fps` metadata but did not end the
  automation session cleanly. At that time, iPhone 12 Pro retest was blocked
  until the device was unlocked; Xiaomi 2201116PG install is blocked by
  user-restricted install;
  Samsung S7 baseline and 60 fps capture plus S10e 60 fps hit native
  Samsung/Exynos Camera3 buffer errors. Keep this issue open.
- 2026-06-07 rerun note:
  `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/summary.md`
  records the latest matrix after automation batching, active session-end, and
  camera timeout fixes. S10e `standard1080p30` now passes including session end,
  including a final current-build smoke after reinstalling the debug APK. S10e
  `sport1080p60`, S7 `standard1080p30`, and S7 `compat720p30` fail with bounded
  timeouts instead of hanging. iPad still passes capture but reports saved-video
  metadata unavailable. At that time, iPhone 12 Pro remained blocked by
  Xcode/debug launch plus locked-device direct launch. Xiaomi remains blocked by
  `INSTALL_FAILED_USER_RESTRICTED`. Keep this issue open.
- 2026-06-07 one-by-one rerun note:
  `logs/verification-runs/20260607-all-devices-one-by-one-rerun/summary.md`
  records a fresh per-device pass. macOS, physical iPad, and Samsung S10e have
  current smoke evidence. iOS simulator launches but has no camera. At that
  time, iPhone 12 Pro remained blocked by locked-device launch/no bridge
  discovery, Samsung S7 still failed baseline `compat720p30` capture with
  Exynos camera wait timeouts, and Xiaomi remained blocked by user-restricted
  APK install. Keep this issue open.
- 2026-06-07 remaining-blockers rerun note:
  `logs/verification-runs/20260607-remaining-blockers-rerun/summary.md` records
  fresh checks for the still-unverified devices. S7 also fails at
  `dataSaver480p30` after camera initialization with a 12 second photo timeout
  and Exynos/Camera2 reopening logs. At that time, iPhone 12 Pro direct launch
  was still denied while locked. Xiaomi still fails install with
  `INSTALL_FAILED_USER_RESTRICTED`. The later new-devices rerun note supersedes
  the iPhone lock blocker for debug automation capture. Keep this issue open.
- 2026-06-07 new-devices rerun note:
  `logs/verification-runs/20260607-new-devices-rerun/summary.md` records fresh
  checks after additional devices were connected. iPhone 12 Pro / iOS 26.5 now
  passes debug automation capture on the 0.5x path for both `sport1080p60` and
  `detail4k30`, but saved-video metadata remains unavailable. A newly connected
  Samsung S10e / Android 12 passes `standard1080p30` with `1920x1080, unknown
  fps` metadata. A newly connected Samsung SM-G960F / Android 10 fails before
  photo save at both `standard1080p30` and `compat720p30` with CameraX
  `ImageCaptureException: Not bound to a valid Camera`. Samsung S7 still fails
  even at `dataSaver480p30` with 12 second photo timeout plus Exynos/Camera2
  reopen logs. Keep this issue open until iOS metadata or a documented
  unavailable limitation is accepted and S7/Samsung low-end CameraX handling is
  resolved or scoped out.
- 2026-06-07 post-label matrix note:
  `logs/verification-runs/20260607-post-label-device-matrix/summary.md` records
  the current matrix after changing the profile selector to display concrete
  target text. macOS, both S10e devices, G960F, iPhone 12 Pro, and physical iPad
  have current one-device smoke evidence. `videoCaptureTarget` now appears as
  `1080p at 30 fps` or `1080p at 60 fps` in settings evidence. G960F now passes
  baseline `standard1080p30`, superseding its earlier failure. S7 remains the
  only connected physical mobile device failing before photo save; iOS metadata
  remains unavailable; iOS simulator remains launch/UI-only because it exposes
  no cameras. Keep this issue open.
- 2026-06-07 parallel matrix note:
  `logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/summary.md`
  records a coordinated independent-capture matrix with a shared command
  barrier. iPhone 12 Pro, iPad 5, macOS, both S10e devices, and G960F passed
  their local lens/profile targets; iOS simulator remained launch-only; S7 was
  classified from logcat as `s7_exynos_camera_timeout`. This is not a
  master/slave discovery proof, so keep this issue open until a separate
  one-master/many-slaves matrix passes or is explicitly scoped out.
- 2026-06-09 settings migration cleanup note:
  `logs/verification-runs/20260609-0522-settings-legacy-camera-quality-migration-cleanup/`
  turns the legacy `cameraQuality` fallback into a real one-time migration to
  the canonical `videoCaptureProfile` preference while keeping an already stored
  canonical profile authoritative. This is local preference cleanup only; keep
  the device-validation issue open.
- 2026-06-09 settings legacy-writer cleanup note:
  `logs/verification-runs/20260609-0530-settings-legacy-camera-quality-writer-cleanup/`
  routes the old `SettingsService` camera-quality getter/setter through
  canonical `videoCaptureProfile` storage and clears stale `cameraQuality`
  values when a canonical profile is stored. This is local preference cleanup
  only; keep the device-validation issue open.

### 1. Validate iOS release/profile launch and capture readiness

- Source: current repo status; related `FALLOS Y MEJORAS` rows 12, 13, 15, 16,
  17.
- Labels: `hydracam`, `mobile`, `ios`, `release-blocker`.
- Priority: High.
- Body: The prior broad "physical iOS white screen" blocker is superseded by
  newer evidence. `logs/verification-runs/2026-06-06-iphone-personal-team-debug/`
  shows iPhone 12 Pro debug launch, session creation, photo capture/upload, and
  video start. `logs/verification-runs/20260606-2310-ipad-capture-failure-trace-and-repro/`
  shows physical iPad photo/video capture passing after the no-flash camera fix.
  Related sheet rows still describe iOS networking, disconnect, and
  role-selection issues that need targeted validation if they remain
  reproducible.
- Acceptance checks: intended-team signed profile/release build reaches the
  expected first app screen from the device icon, photo and video capture work
  or produce actionable logs, simulator behavior remains unchanged, and at
  least one two-device master/slave smoke run is recorded before production
  claims.
- 2026-06-09 connected-iPad note:
  `logs/verification-runs/20260609-0021-ipad-physical-release-profile-smoke/`
  shows the connected iPad (5) / iOS 17.7.11 passing Profile build/install and
  no-tooling launch through `devicectl`, warming an identity-matched automation
  bridge at `169.254.193.202:4762`, and passing one-device master photo/video
  capture with copied iPad JPEG/MP4 evidence. Keep this issue open until the
  intended-team icon launch and at least one two-device iOS master/slave smoke
  run are recorded.
- 2026-06-09 runtime-screenshot note:
  `logs/verification-runs/20260609-0120-ipad-runtime-screenshot-boundary-route-replacement/`
  fixes and proves the follow-up from the connected-iPad run where
  `capture_screenshot` failed after runtime `set_role` into master because the
  automation `RepaintBoundary` lived on the removable home route. The app now
  wraps the `MaterialApp` navigator instead; the updated iPad Profile build
  returned `capture_screenshot` success before and after `set_role`, copied
  standby/master screenshots, copied bridge logs, recorded a local iPad MP4,
  and passed `flutter analyze --no-pub` plus focused widget/app-shell tests.
  Keep this issue open only for the intended-team icon launch and at least one
  two-device iOS master/slave smoke run.

### 2. Preserve session state across master reconnect

- Source: `FALLOS Y MEJORAS` row 22 / `(EN)` row 10.
- Original: "reset session on reconnect" after disconnecting master and
  returning to master screen, slave still shows session but loses materials.
- Labels: `hydracam`, `mobile`, `session`, `websocket`.
- Priority: High.
- Acceptance checks: reconnecting to the same active session does not clear
  captured media, metadata remains consistent on master and slave, and a test or
  reproducible manual script covers the flow.
- 2026-06-08 same-session rejoin note:
  `logs/verification-runs/20260608-1834-same-session-rejoin-preserves-media/`
  adds regression coverage so `SessionManager.startSession()` preserves captured
  media and the uploader queue when the same active session GUID is announced
  again, while a different GUID still starts clean. Keep this issue open for a
  real master/slave reconnect reproduction pack and metadata comparison across
  devices.
- 2026-06-08 session-mismatch-diagnostics note:
  `logs/verification-runs/20260608-2115-slave-session-mismatch-diagnostics/`
  adds the active slave `sessionGuid` to slave registration and heartbeat
  messages, stores it in master connected-device diagnostics, and labels slaves
  as `Different session` when their reported session differs from the master
  session. Keep this issue open for real master/slave reconnect reproduction
  and cross-device metadata comparison.
- 2026-06-17 stale-session-label diagnostics note:
  focused connected-client automation coverage now keeps the machine-readable
  stale slave session comparison as `different` or `matching`, but labels
  disconnected rows as historical, for example
  `Last reported: Different session`, instead of presenting stale session
  state as live. The master known-device modal uses the same shared label. Keep
  this issue open for real master/slave reconnect reproduction and cross-device
  metadata comparison.
- 2026-06-09 metadata-write-serialization note:
  `logs/verification-runs/20260609-0155-session-metadata-write-serialization-cleanup/`
  removes the `SessionManager.updateMetadata()` concurrency TODO by capturing
  the session metadata payload before async filesystem work and serializing
  metadata writes through a FIFO queue. The focused regression delays the
  path lookup, switches sessions, and proves the pending old-session save writes
  to the old session directory instead of the new one. Keep this issue open for
  real master/slave reconnect reproduction and cross-device metadata comparison.
- 2026-06-09 session-add-media async cleanup note:
  `logs/verification-runs/20260609-0228-session-add-media-async-return-cleanup/`
  changes `SessionManager.addPhoto()` and `addVideo()` from hidden
  fire-and-forget side-effect methods to awaitable `Future<void>` operations
  that complete after metadata persistence and uploader enqueue. Focused
  session and platform orchestration tests now await those effects directly.
  Keep this issue open for real master/slave reconnect reproduction and
  cross-device metadata comparison.
- 2026-06-09 master-session-response-helper note:
  `logs/verification-runs/20260609-0211-master-session-status-response-helper-cleanup/`
  centralizes the master's `sessionStatus` / `noSession` response payloads and
  routes both registered-client and explicit `getSessionStatus` paths through
  the same sender. Focused tests prove active and inactive session payloads.
  Keep this issue open for real master/slave reconnect reproduction and
  cross-device metadata comparison.
- 2026-06-09 master-screen async handler cleanup note:
  `logs/verification-runs/20260609-0334-master-screen-async-handler-cleanup/`
  adds focused widget coverage for `MasterScreen` backend session creation and
  the local-master recording preview route, then converts the remaining
  `MasterScreen` async UI handlers to awaitable methods dispatched explicitly
  from button callbacks. Keep this issue open for real master/slave reconnect
  reproduction and cross-device metadata comparison.
- 2026-06-09 master-server stop lifecycle cleanup note:
  `logs/verification-runs/20260609-0350-master-server-stop-lifecycle-contract-cleanup/`
  resolves the `MasterServer.stopServer()` session-ending TODO by documenting
  and testing it as transport cleanup only. The focused regression proves
  socket/client state is cleared while the active session remains alive until
  `endCurrentSession()` is called explicitly. Keep this issue open for real
  master/slave reconnect reproduction and cross-device metadata comparison.
- 2026-06-09 master-screen dispose lifecycle cleanup note:
  `logs/verification-runs/20260609-0353-master-screen-dispose-lifecycle-contract-cleanup/`
  makes `MasterScreen` server/announcer dependencies injectable for focused
  lifecycle tests, documents screen disposal as UI/server resource cleanup only,
  and fixes the `MasterServer.startServer()` / `stopServer()` race where an
  async bind could complete after stop was requested. Focused regressions prove
  pending startup is closed instead of activated, and active sessions survive
  screen disposal until `endCurrentSession()` runs explicitly. Keep this issue
  open for real master/slave reconnect reproduction and cross-device metadata
  comparison.
- 2026-06-09 automation service-session cleanup note:
  `logs/verification-runs/20260609-0517-automation-local-only-guard-cleanup/`
  removed the former local-only automation path and tightened the static
  service-session script contract so capture scripts still cannot disable
  uploads. Keep this issue open for real master/slave
  reconnect reproduction and cross-device metadata comparison.
- 2026-06-18 session/upload-state cleanup note:
  `logs/verification-runs/20260618-1314-session-upload-state-debug-cleanup/`
  proves the runtime local-session split has been removed behind one
  service-session model with computed upload state, debug-session labeling,
  debug cleanup registry/client contracts, and a no-local-session static guard.
  Local/static validation passed; keep this issue open for live debug
  capture/upload deletion proof plus real master/slave reconnect reproduction
  and cross-device metadata comparison.
- 2026-06-17 slave no-session authority note:
  focused `SlaveClient` coverage now proves a master's `noSession` response
  preserves an active slave service session and queued media instead of
  silently ending the active session. Additional conflict coverage proves a
  master-reported different session GUID is surfaced and rejected instead of
  silently switching the slave into the other session. `sessionEnded` remains
  the explicit destructive authority. Keep this issue open for real
  master/slave reconnect reproduction and cross-device metadata comparison.
- 2026-06-17 slave session-media heartbeat diagnostics note:
  focused slave and master-parser coverage now proves slave heartbeats include
  a compact `sessionMedia` summary (`photoCount`, `videoCount`,
  `pendingUploadCount`, `uploadedCount`) and the master preserves that summary
  in connected-client automation payloads. Keep this issue open for real
  master/slave reconnect reproduction and cross-device metadata comparison.
- 2026-06-17 identify session-media diagnostics note:
  focused slave and master-parser coverage now proves `identifyAck` carries
  the same compact `sessionMedia` summary as heartbeat and refreshes the
  master connected-client diagnostics after an operator identify request. Keep
  this issue open for real master/slave reconnect reproduction and cross-device
  metadata comparison.
- 2026-06-18 stale session-media diagnostics note:
  `logs/verification-runs/20260618-1522-stale-session-media-diagnostics/`
  adds a regression for a slave heartbeat that previously reported an active
  session with `sessionMedia`, then later reports no active session. Master
  connected-client diagnostics now clear the cached media summary instead of
  showing stale pending/uploaded counts beside a null reported session. Keep
  this issue open for real master/slave reconnect reproduction and cross-device
  metadata comparison.
- 2026-06-17 reported-session modal diagnostics note:
  focused `MasterScreen` coverage now proves the known-device modal shows the
  exact slave-reported session GUID beside the status label, so operators can
  compare master/slave metadata without relying only on `Same session` or
  `Different session`. Keep this issue open for real master/slave reconnect
  reproduction and cross-device metadata comparison.
- 2026-06-17 master stale-session command guard note:
  focused `MasterServer` coverage now proves broadcast capture commands skip
  connected slaves that explicitly report a different active session GUID while
  still reaching matching-session slaves. Identify remains available for those
  stale-session slaves so operators can refresh diagnostics and recover the
  device without first sending capture/upload commands into the wrong session.
  Keep this issue open for real master/slave reconnect reproduction and
  cross-device metadata comparison.

### 3. Prevent stale uploads from crossing sessions

- Source: `FALLOS Y MEJORAS` row 2, completed in sheet but important enough to
  keep as regression protection.
- Labels: `hydracam`, `mobile`, `upload`, `session`, `testing`.
- Priority: High.
- Acceptance checks: ending a session before uploads finish cannot attach media
  to the next session; uploader queue reset behavior is covered by test or
  manual validation.
- 2026-06-08 implementation note:
  `logs/verification-runs/20260608-1756-uploader-reset-progress-hygiene/`
  adds regression coverage for `UploaderService.reset()` and clears stale
  visible upload progress along with queue/current upload/estimated time state.
  Keep this issue open for deeper in-flight upload/session GUID cancellation or
  server-side race proof.
- 2026-06-08 in-flight reset note:
  `logs/verification-runs/20260608-1918-stale-inflight-upload-reset-guard/`
  adds an upload-generation guard so a previous session's in-flight HTTP
  completion is ignored after `UploaderService.reset()`, leaving the old media
  unuploaded and the new session metadata untouched. Keep this issue open for
  server-side race proof.
- 2026-06-17 reset transport cancellation note:
  `logs/verification-runs/20260617-1929-uploader-reset-cancels-transport/`
  proves `UploaderService.reset()` closes the active `HydraCamApiService` HTTP
  client while an upload request is in flight, then keeps the existing
  upload-generation guard so the stale completion cannot mark old media
  uploaded after session reset. Keep this issue open for live server-side race
  proof.

### 4. Improve upload failure, cancel, requeue, and progress UI

- Sources: `FALLOS Y MEJORAS` rows 23, 25; `JAVI IMMEDIATE BACKLOG` rows 102,
  113, 114; `Functional Requirements` FR-048.
- Labels: `hydracam`, `mobile`, `upload`, `ux`.
- Priority: Medium.
- Body: Show upload failure state in media lists, support cancel/requeue from
  uploader screen, estimate upload time from bytes uploaded, send start-upload
  commands, and expose slave upload info.
- Acceptance checks: failed uploads show a visible state, long press or explicit
  action can cancel and requeue, progress includes bytes/time when available,
  and auto/manual upload paths remain compatible.
- 2026-06-08 implementation note:
  `logs/verification-runs/20260608-1759-failed-upload-visible-state/` adds a
  distinct failed-upload label and red error icon in `MediaListWidget`, plus a
  focused widget test, screenshot, and video proof. Keep this issue open for
  cancel/requeue controls, bytes/time estimates, start-upload commands, and
  slave upload info.
- 2026-06-08 byte-progress note:
  `logs/verification-runs/20260608-1804-upload-byte-progress-visible/` adds
  byte-level progress text for the currently uploading media item, with a
  focused widget test plus screenshot and video proof. Keep this issue open for
  time estimates, cancel/requeue controls, start-upload commands, and slave
  upload info.
- 2026-06-08 requeue-action note:
  `logs/verification-runs/20260608-1807-explicit-upload-requeue-actions/`
  labels the existing media-list requeue actions as `Retry upload` for failed
  media and `Queue upload` for pending media, with callback coverage plus
  screenshot and video proof. Keep this issue open for true cancel controls,
  time estimates, start-upload commands, and slave upload info.
- 2026-06-08 time-estimate note:
  `logs/verification-runs/20260608-1830-upload-time-estimate-visible/` adds a
  deterministic estimated-time-remaining label for the current upload when
  progress and upload start time are known, keeps byte progress visible, and
  moves the estimate into the subtitle to avoid trailing progress overflow.
  Keep this issue open for true cancel controls, start-upload commands, and
  slave upload info.
- 2026-06-08 pending-cancel note:
  `logs/verification-runs/20260608-1843-pending-upload-cancel-control/` adds
  `UploaderService.cancelQueuedMedia()` plus a media-list cancel action wired
  from `UploaderInfoScreen` for media that is still pending in the upload queue.
  Keep this issue open for in-flight network cancellation, start-upload
  commands, and slave upload info.
- 2026-06-08 start-upload-command note:
  `logs/verification-runs/20260608-1855-start-upload-all-slave-command/` wires
  the slave WebSocket `startUploadingAll` command to the existing manual
  uploader path and proves queued media is consumed by the command handler.
  Keep this issue open for in-flight network cancellation and slave upload info.
- 2026-06-08 slave-upload-info note:
  `logs/verification-runs/20260608-1922-slave-upload-info-action/` adds a
  direct `Uploader Info` action to `SlaveScreen` in portrait and landscape
  layouts, routes it to the existing uploader status screen, and proves the
  path with a focused widget test plus screenshot/video evidence. Keep this
  issue open for in-flight network cancellation.
- 2026-06-08 in-flight-cancel note:
  `logs/verification-runs/20260608-1933-inflight-upload-cancel-control/` adds
  active-upload cancellation from the uploader UI, clears current/progress
  state through `UploaderService.cancelCurrentUpload()`, closes and replaces
  the active HTTP client through `HydraCamApiService.cancelInFlightRequests()`,
  and proves late upload completion cannot mark the media uploaded after
  cancellation. This completes the listed mobile-side upload UI slices for item
  4; keep production closure gated on a real-device upload smoke run.
- 2026-06-17 master-start-uploads control note:
  focused `MasterScreen` coverage now proves the active master session exposes
  a `Start Uploads` control that dispatches `startUploadingAll` to slaves and
  drains the master's local uploader queue through the same manual upload path.
  Keep production closure gated on a real-device plus live-backend upload smoke
  run.
- 2026-06-17 active-cancel reason note:
  focused `UploaderService` coverage now proves active upload cancellation sets
  a specific retryable media failure reason, `Upload cancelled.`, instead of
  leaving the media in a generic failed state after current/progress transport
  state is cleared. Keep production closure gated on a real-device upload smoke
  run.
- 2026-06-17 queued-cancel reason note:
  focused `UploaderService` coverage now proves queued upload cancellation also
  stamps the media as `Upload cancelled.` and sets failure-state timing before
  removing it from the pending queue, so the media list can present retryable
  cancellation instead of leaving it as an ordinary pending upload. Keep
  production closure gated on a real-device upload smoke run.
- 2026-06-17 queued-cancel UI refresh note:
  focused `UploaderInfoScreen` coverage now proves tapping cancel on a queued
  media row immediately re-renders the row as retryable `Upload cancelled.`
  state and removes the cancel action, instead of waiting for another unrelated
  notifier rebuild. Keep production closure gated on a real-device upload smoke
  run.
- 2026-06-17 uploader-summary state note:
  focused `UploaderInfoScreen` coverage now proves the uploader screen surfaces
  pending queue depth and the current upload filename in the summary area,
  alongside uploaded photo/video counts and estimated remaining time. Keep
  production closure gated on a real-device plus live-backend upload smoke run.
- 2026-06-17 uploader-screen start action note:
  focused `UploaderInfoScreen` coverage now proves the uploader status surface
  can start all pending uploads directly, awaits the manual upload drain, and
  refreshes the queue summary after the pending queue reaches zero. Keep
  production closure gated on a real-device plus live-backend upload smoke run.
- 2026-06-17 cancellation metadata durability note:
  focused `UploaderService` coverage now proves both queued and active upload
  cancellation write `Upload cancelled.` into current session metadata before
  session end, so retryable cancellation state survives screen changes and
  restore paths. Keep production closure gated on a real-device upload smoke
  run.
- 2026-06-18 cancel-resumes-queue note:
  `logs/verification-runs/20260618-1447-uploader-cancel-resumes-queue/`
  adds a regression for a manual upload drain with two queued media items:
  cancelling the active upload now leaves the cancelled item retryable and
  continues uploading the remaining queued item after the stale HTTP completion
  is ignored. `UploaderService.reset()` remains a hard stop and clears the
  resume marker. Keep production closure gated on a real-device plus
  live-backend upload smoke run.

### 5. Add critical battery autostop

- Sources: `JAVI IMMEDIATE BACKLOG` row 119; `FALLOS Y MEJORAS` row 38.
- Labels: `hydracam`, `mobile`, `battery`, `recording`.
- Priority: High.
- Acceptance checks: when battery becomes critical during recording, recording
  stops safely, user sees a meaningful message, logs are written through
  `LogService`, and non-critical low-battery warnings are throttled.
- 2026-06-08 implementation note:
  `logs/verification-runs/20260608-1745-critical-battery-autostop/` adds the
  critical battery threshold, one-shot autostop callback, camera forced-stop
  path, LogService coverage, snackbar screenshot, and video proof from a
  simulated Flutter app surface. Keep this issue open until a real-device or
  emulator recording run proves the platform battery event stops an active
  recording with device logs.
- 2026-06-09 forced-stop helper cleanup note:
  `logs/verification-runs/20260609-0340-camera-forced-stop-helper-cleanup/`
  unifies the camera storage and battery forced-stop paths behind one helper,
  preserves their distinct notification/log text, and adds focused mock-camera
  coverage that both paths stop recording, flag interruption, and persist the
  captured video in the active session. Keep this issue open for real-device or
  emulator recording proof from platform battery/storage events.
- 2026-06-09 storage callback cleanup note:
  `logs/verification-runs/20260609-0533-storage-critical-callback-future-cleanup/`
  types the critical-storage callback as `FutureOr<void>` and runs it through a
  guarded fire-and-forget helper so callback failures are logged instead of
  escaping storage-level handling. Keep this issue open for real-device or
  emulator recording proof from platform battery/storage events.
- 2026-06-17 storage critical trigger log note:
  focused `StorageService` coverage now proves the service logs the available
  storage value when critical storage first blocks recording and triggers the
  forced-stop callback, matching the battery autostop trigger diagnostics. Keep
  this issue open for real-device or emulator recording proof from platform
  battery/storage events.
- 2026-06-18 resource warning diagnostics note:
  `logs/verification-runs/20260618-1342-resource-warning-diagnostics/` reruns
  focused storage coverage, analyzer, and the full Flutter test suite after
  keeping the critical-storage trigger value in `LogService` and aligning the
  battery/storage/alert warning snackbars with the shared HydraCam warning and
  danger surfaces. Keep this issue open for real-device or emulator recording
  proof from platform battery/storage events.

### 6. Make network/device identity visible

- Sources: `FALLOS Y MEJORAS` rows 13, 27, 41; `JAVI IMMEDIATE BACKLOG` row
  115.
- Labels: `hydracam`, `mobile`, `network`, `ux`.
- Priority: Medium.
- Body: Show device IP, short device ID, disconnected state, app version,
  hardware identity where feasible, and current network/Wi-Fi context.
- Acceptance checks: master device list and relevant diagnostics make it clear
  which network and devices are active, with graceful behavior when platform
  APIs cannot expose SSID.
- 2026-06-08 implementation note:
  `logs/verification-runs/20260608-1751-device-identity-diagnostics/` adds
  active session diagnostics for network/IP, short device ID, app version
  fallback, and hardware identity fallback, with widget tests plus screenshot
  and video proof. Keep this issue open for disconnected-device state and
  broader master device-list UX refinements.
- 2026-06-08 disconnected-state note:
  `logs/verification-runs/20260608-1910-disconnected-device-state-master-list/`
  retains known slave diagnostics after a socket disconnect, marks the row
  `Disconnected`, keeps live connected IDs/count socket-only, and exposes the
  state in the master modal and automation payload. Keep this issue open for
  broader master device-list UX refinements.
- 2026-06-08 master-device-list-summary note:
  `logs/verification-runs/20260608-2030-master-device-list-summary-sort/` adds
  known/live/disconnected summary counts to the connected-client automation
  payload, sorts live devices before disconnected history in
  `MasterServer.getConnectedDeviceInfos()`, and changes the master modal title
  to `Known Devices` with a live/stale summary. Keep this issue open for
  real-device network smoke evidence and any future multi-group network UX.
- 2026-06-09 master-announcer lifecycle cleanup note:
  `logs/verification-runs/20260609-0527-master-announcer-lifecycle-cleanup/`
  makes the UDP discovery announcer testable with injected timer/sender
  dependencies, proves stop cancels the periodic timer, and proves one broadcast
  error does not prevent later ticks. Keep this issue open for actual LAN
  discovery behavior, real-device network smoke evidence, and multi-group
  network UX.
- 2026-06-17 disconnected-identify diagnostics note:
  focused `MasterServer` and automation-payload coverage now proves a pending
  `identifySlave` request becomes `Identify unavailable: disconnected` when the
  slave disconnects before acknowledging, instead of leaving the stale row at
  `Identify requested` indefinitely. Follow-up coverage also proves a
  previously acknowledged identify request on a disconnected row is labeled
  `Last reported: Identify acknowledged` instead of presenting the
  acknowledgement as live. Keep this issue open for real-device network smoke
  evidence and multi-group network UX.
- 2026-06-17 stale-network-label diagnostics note:
  focused connected-client automation coverage now proves disconnected devices
  keep their machine-readable last network status but label it as historical,
  for example `Last reported: Ready`, instead of presenting stale readiness as
  current. The master known-device modal uses the same label. Keep this issue
  open for real-device network smoke evidence and multi-group network UX.
- 2026-06-17 slave-app-hardware-registration note:
  focused master/slave coverage now proves slave registration can carry
  `appVersion`, `appBuildNumber`, and `hardware` into master connected-device
  diagnostics; the automation payload exposes `appVersion`, `appBuildNumber`,
  and `hardwareLabel`, and the known-device modal shows App/Hardware rows with
  fallbacks. Keep this issue open for real-device network smoke evidence and
  multi-group network UX.
- 2026-06-17 known-device session-media modal note:
  focused `MasterScreen` coverage now proves the known-device modal surfaces
  each slave's compact session media summary, for example
  `Media: 2 photos, 1 video, 1 pending, 2 uploaded`, and the diagnostics sheet
  scrolls instead of overflowing as rows grow. Keep this issue open for
  real-device network smoke evidence and multi-group network UX.
- 2026-06-17 known-device recency modal note:
  focused `MasterScreen` coverage now proves the known-device modal surfaces
  each slave's registered and last-seen timestamps alongside app, hardware,
  network, preview, session, and media diagnostics. Keep this issue open for
  real-device network smoke evidence and multi-group network UX.
- 2026-06-18 master diagnostics coverage note:
  `logs/verification-runs/20260618-1349-master-device-diagnostics-coverage/`
  reruns focused `MasterServer` coverage, analyzer, and the full Flutter test
  suite for app/hardware registration diagnostics, heartbeat session-media
  payloads, identify acknowledgement network/session/media updates,
  disconnected identify and preview labels, and stale-session capture filtering.
  Keep this issue open for real-device network smoke evidence and multi-group
  network UX.

### 7. Support synchronized time accurately enough for capture

- Sources: `FALLOS Y MEJORAS` rows 28, 43; `Functional Requirements` FR-047;
  `Testing table` T-019.
- Labels: `hydracam`, `mobile`, `sync`, `testing`.
- Priority: Medium.
- Body: Existing scheduled commands reduced the timer problem, but source notes
  still ask for NTP/native time correction and comparable delays across nodes.
- Acceptance checks: devices can estimate or synchronize clock offsets, command
  scheduling uses corrected time, and test evidence records capture start
  skew target.
- 2026-06-08 corrected-scheduler note:
  `logs/verification-runs/20260608-1826-scheduled-task-clock-offset/` adds an
  explicit clock-offset primitive to `ScheduledTaskService`, verifies corrected
  delay calculations and immediate/cancellable scheduling behavior, and routes
  slave scheduled-command timers through the corrected scheduler. Keep this
  issue open for real device clock-offset estimation, master/slave offset
  exchange, and capture-start skew evidence.
- 2026-06-08 scheduled-command-offset note:
  `logs/verification-runs/20260608-2035-scheduled-command-master-time-offset/`
  adds `masterTime` to scheduled-command payloads, verifies master payload
  emission, and proves a loopback slave applies the received master timestamp as
  a `ScheduledTaskService` clock offset before computing corrected countdown
  delay. Keep this issue open for real-device offset estimation and capture
  start-skew evidence.
- 2026-06-09 scheduled-task callback cleanup note:
  `logs/verification-runs/20260609-0301-scheduled-task-future-callback-cleanup/`
  changes `ScheduledTaskService.scheduleTask()` to take a typed async-capable
  callback and return an awaitable `Future<void>`. The focused regression proves
  past-due async callbacks can be awaited through completion, and the slave
  scheduled-command path marks future timer execution as deliberately
  unawaited. Keep this issue open for real-device offset estimation and capture
  start-skew evidence.
- 2026-06-09 scheduled-task cancel future cleanup note:
  `logs/verification-runs/20260609-0310-scheduled-task-cancel-future-cleanup/`
  completes the returned `Future<void>` when a pending scheduled task is
  cancelled or replaced, while preserving callback suppression and scheduler
  removal. This prevents awaitable scheduling callers from hanging on a
  cancelled timer. Keep this issue open for real-device offset estimation and
  capture start-skew evidence.
- 2026-06-09 scheduled-task past-due replacement cleanup note:
  `logs/verification-runs/20260609-0502-scheduled-task-past-due-replacement-cleanup/`
  moves same-ID cancellation ahead of immediate past-due execution in
  `ScheduledTaskService.scheduleTask()`, so replacing a pending timer with an
  already-due task settles the stale future and removes the old timer before the
  replacement callback runs. Focused scheduler coverage first reproduced the
  hanging stale future, then passed with the unified replacement path. Keep this
  issue open for real-device offset estimation and capture start-skew evidence.
- 2026-06-18 master time-sync clock injection note:
  `logs/verification-runs/20260618-1453-master-time-sync-clock-injection/`
  injects the master clock used for `timeSyncResponse` receive/send timestamps,
  adds deterministic `t1`/`t2` coverage for the master response path, and reruns
  focused master/slave/scheduler/integration time-sync tests plus full analyzer
  and full Flutter tests. Keep this issue open for real-device offset
  estimation and capture start-skew evidence.

### 8. Implement auto-record mode

- Sources: `JAVI IMMEDIATE BACKLOG` rows 68, 71, 82; sprint future rows 20-21.
- Labels: `hydracam`, `mobile`, `session`, `recording`, `unattended`.
- Priority: Medium.
- Body: Add a setting for auto-record/unattended mode so devices start
  recording automatically when slaves connect to a master with an active
  session.
- Acceptance checks: setting is editable, disabled by default unless product
  decides otherwise, auto-start happens only under clear active-session
  conditions, and users can stop recording safely.
- 2026-06-08 implementation note:
  `logs/verification-runs/20260608-1809-autograbado-setting-toggle/` adds the
  persisted `Auto-record mode` setting, disabled by default, plus focused
  SettingsService/SettingsScreen tests, screenshot, and video proof. The same
  proof caught and fixed a narrow settings-row overflow. Keep this issue open
  for active-session auto-start behavior and safe stop controls.
- 2026-06-08 auto-start note:
  `logs/verification-runs/20260608-1848-autograbado-session-autostart/` wires
  slave `sessionStarted` / `sessionStatus` handling through the persisted
  `Auto-record mode` setting and proves the mock slave starts recording after
  joining an active session. Keep this issue open for real-device unattended
  recording proof and safe stop controls.
- 2026-06-08 slave-safe-stop note:
  `logs/verification-runs/20260608-2045-slave-recording-safe-stop-control/`
  adds a recording-surface stop button on `SlaveScreen`, routes it through the
  existing local slave stop-recording command path, and proves the widget
  dispatches one stop call before returning to `Recording stopped.` state. Keep
  this issue open for real-device unattended recording proof.
- 2026-06-09 master-video stop handler cleanup note:
  `logs/verification-runs/20260609-0323-master-video-stop-handler-async-cleanup/`
  adds focused widget coverage that the master recording-preview stop button
  awaits `onStopRecording` and returns the captured video through Navigator,
  then converts the stop handler to `Future<void>` with explicit `unawaited`
  dispatch. Keep this issue open for real-device unattended recording proof.
- 2026-06-09 slave dim-timer cleanup note:
  `logs/verification-runs/20260609-0327-slave-dim-timer-async-cleanup/`
  adds slave-screen widget coverage for screen auto-off dimming during
  recording and tap-to-wake reset, then converts the dim timer helpers to
  `Future<void>` with mounted guards and explicit async dispatch. Keep this
  issue open for real-device unattended recording proof.

### 9. Improve old-media/gallery session attachment

- Sources: `FALLOS Y MEJORAS` rows 32, 44, 45, 46; `JAVI IMMEDIATE BACKLOG` row
  84.
- Labels: `hydracam`, `mobile`, `gallery`, `session`.
- Priority: Medium.
- Body: Loading old media should permit filters but not require them. The app
  should help identify videos close to previous sessions and allow attaching
  likely matching media.
- Acceptance checks: gallery can load without a mandatory specific filter,
  candidate session matching uses a clear time window, and attaching media does
  not corrupt existing session metadata.
- 2026-06-08 matching-window note:
  `logs/verification-runs/20260608-1816-gallery-session-window-matcher/` adds
  a reusable gallery video-to-session matcher with an explicit margin window,
  nearest-first ranking, outside-window exclusion, focused unit tests, and
  screenshot/video proof. Keep this issue open for optional unfiltered gallery
  browsing, surfacing candidate sessions in the media-selection UI, and
  attachment metadata corruption proof.
- 2026-06-08 browse-all note:
  `logs/verification-runs/20260608-1838-gallery-browse-all-filter-action/`
  adds a `Browse All` action to `MediaFilterDialog` so old media import can
  proceed with no date or duration constraints while the filtered `Apply` action
  remains available. Keep this issue open for candidate-session display and
  attach-metadata corruption proof.
- 2026-06-08 scan-preserves-active-session note:
  `logs/verification-runs/20260608-1944-gallery-scan-active-session-preserved/`
  fixes `SessionManager.scanAndReconstructSessions()` so old-media/session
  reconstruction restores the active session GUID and device type after scanning
  historical media folders, and only treats final path segments starting with
  `session_` as session folders. This prevents gallery/old-media scans from
  corrupting active session context while reconstructing metadata. Keep this
  issue open for candidate-session display and real gallery attachment smoke
  evidence.
- 2026-06-08 candidate-label note:
  `logs/verification-runs/20260608-1948-gallery-candidate-session-labels/`
  adds a range-based matcher entrypoint and surfaces the nearest candidate
  session label on video tiles in `MediaSelectionScreen`; the gallery import
  path passes the active session without loading historical metadata. Keep this
  issue open for historical-session candidate sourcing and real gallery
  attachment smoke evidence.
- 2026-06-08 historical-candidate-source note:
  `logs/verification-runs/20260608-1953-gallery-historical-session-candidate-source/`
  adds side-effect-free session metadata snapshots and a
  `GallerySessionCandidateSource` that returns the active session plus
  historical session metadata once, then passes those candidates into gallery
  media selection. Keep this issue open for real gallery attachment smoke
  evidence.
- 2026-06-09 session-restore-helper note:
  `logs/verification-runs/20260609-0145-session-restore-helper-cleanup/`
  centralizes previous-session metadata restore in `SessionManager`, updates
  both `SessionDetailsScreen` load actions to call the shared restore path, and
  proves restored photos/videos are re-queued exactly once while preserving the
  caller-selected role. Keep this issue open for real gallery attachment smoke
  evidence.
- 2026-06-09 add-gallery-button handler cleanup note:
  `logs/verification-runs/20260609-0313-add-gallery-media-button-async-handler-cleanup/`
  adds widget coverage for the active-session gallery button opening the media
  filter dialog, then converts the private async button/dialog handlers to
  `Future<void>` with explicit `unawaited` dispatch from `onPressed`. Keep this
  issue open for real gallery attachment smoke evidence.
- 2026-06-09 session-details handler cleanup note:
  `logs/verification-runs/20260609-0317-session-details-async-handler-cleanup/`
  adds widget coverage for the unsent-media upload confirmation callback in
  `SessionDetailsScreen`, then converts both session-load handlers to
  `Future<void>` with explicit `unawaited` UI dispatch. Keep this issue open
  for real gallery attachment smoke evidence.
- 2026-06-09 previous-sessions refresh lifecycle cleanup note:
  `logs/verification-runs/20260609-0320-previous-sessions-refresh-lifecycle-cleanup/`
  adds a regression for late previous-session refresh completion after
  `PreviousSessionsScreen` is disposed, then guards the post-scan `setState`
  path and makes init, refresh, and tap async dispatch explicit. Keep this
  issue open for real gallery attachment smoke evidence.
- 2026-06-17 previous-session preview metadata note:
  focused `SessionManager` coverage now proves `loadSessionMetadata()` previews
  historical metadata without replacing the active session GUID, current
  session, or device role. Explicit previous-session restore and upload still
  go through `restoreSessionFromMetadata()`. Keep this issue open for real
  gallery attachment smoke evidence.
- 2026-06-17 session-details video playback note:
  focused `SessionDetailsScreen` coverage now proves tapping a saved video opens
  the existing `VideoPlayerScreen` media dialog instead of the placeholder
  `Video playback is not implemented yet.` message. Keep this issue open for
  real gallery attachment smoke evidence.
- 2026-06-17 gallery candidate timing label note:
  focused `MediaSelectionScreen` coverage now proves video candidate labels show
  both the matched session identifier and the timing relationship, for example
  `Candidate: guid-court-1 - 4 min after session`, so operators can see why old
  media is near a previous session before selecting it. Keep this issue open for
  real gallery attachment smoke evidence.
- 2026-06-17 missing-local-media details note:
  focused `SessionDetailsScreen` coverage now proves historical media rows show
  `Local file missing` when the local path no longer exists and route the upload
  action to the existing missing-file dialog instead of offering the normal
  upload confirmation. Keep this issue open for real gallery attachment smoke
  evidence.
- 2026-06-17 missing-local-media list note:
  focused `MediaListWidget` coverage now proves reusable upload/media rows mark
  missing local photo and video files as `Local file missing` and suppress the
  dead-end queue, retry, and cancel upload actions before the uploader attempts
  an impossible local-file upload. Keep this issue open for real gallery
  attachment smoke evidence.
- 2026-06-17 gallery-attachment copy note:
  focused service and widget coverage now proves selected gallery media is
  copied into the active session directory before session registration, so
  metadata and uploader state point at HydraCam-owned files instead of the
  original gallery asset path. Keep this issue open for real gallery attachment
  smoke evidence.
- 2026-06-17 duplicate-gallery-attachment guard note:
  focused `GallerySessionAttachmentService` coverage now proves re-attaching
  the same selected gallery photo to the same active session leaves exactly one
  session metadata entry for the copied session file, preventing duplicate
  uploader/session records for a repeated gallery import. The same coverage
  also proves duplicate imports and direct copy retries reuse the existing
  session copy instead of overwriting it. Keep this issue open for real gallery
  attachment smoke evidence.
- 2026-06-17 no-op gallery import feedback note:
  focused `AddGalleryMediaButton` coverage now proves selected gallery assets
  with no available local file do not call the attachment service, do not mutate
  session media, and show `No gallery media was added` instead of the normal
  success message. Follow-up coverage proves mixed selections report the number
  of imported items and skipped assets instead of hiding skipped media behind a
  generic success message. Additional coverage proves a failed per-asset
  attachment is logged, counted as skipped, and does not abort later selected
  media in the same import. Gallery provider query failures are now logged and
  reported as `Could not load gallery media` without navigating to selection or
  touching session media. Keep this issue open for real gallery attachment smoke
  evidence.
- 2026-06-18 gallery import durability note:
  `logs/verification-runs/20260618-1325-gallery-session-import-durability/`
  reruns the focused gallery attachment service/widget tests plus analyzer and
  proves permission/save stalls time out, gallery assets are copied to
  session-owned files before registration, duplicates are idempotent, missing
  assets are skipped without session mutation, provider query failures surface
  as user-visible errors, and per-asset import failures do not abort later
  selected media. Keep this issue open for real gallery attachment smoke
  evidence; Flutter wireless discovery could not reach the iPad/iPhone during
  this Tier D run.

### 10. Add user/player assignment to sessions

- Sources: `FALLOS Y MEJORAS` row 35; `JAVI IMMEDIATE BACKLOG` rows 81, 100,
  109; FR-060, FR-061, FR-062.
- Labels: `hydracam`, `mobile`, `users`, `external-backend`.
- Priority: Medium.
- Body: Assign users/players to sessions and support mid-session additions.
  Backend APIs are external dependencies.
- Acceptance checks: mobile UI behavior is defined behind a backend contract,
  player import/source is explicit, and app handles missing backend support
  gracefully.
- 2026-06-08 missing-backend-state note:
  `logs/verification-runs/20260608-2055-session-player-source-missing-backend-state/`
  adds a `Players` status panel to `SessionDetailsScreen` that explicitly shows
  `Source: backend not configured` and `Player assignment unavailable` when no
  session-player API contract is present. Keep this issue open for real backend
  contract selection, player import source, mid-session assignment, and mobile
  integration proof.
- 2026-06-17 player-import-source copy note:
  focused `SessionDetailsScreen` coverage now makes the missing player import
  path explicit by showing `Import source: waiting for session-player API` and
  `Mid-session additions unavailable until FR-061 exists` in the Players panel.
  Keep this issue open for real backend contract selection, player import
  source wiring, mid-session assignment, and mobile integration proof.

### 11. Make mobile Auth0 login recoverable and release-safe

- Source: current repo audit, 2026-06-07; current `AuthService` uses
  `flutter_appauth` and keeps access token, email, and profile picture in memory
  only, while `UserService` keeps logged-in state and user GUID in memory only.
- Labels: `hydracam`, `mobile`, `auth`, `android`, `ios`, `security`,
  `release-blocker`.
- Priority: High.
- Body: The current login succeeds only for the live app process. Implement a
  recoverable authentication session: request refresh-capable scopes if kept on
  Auth0, persist credentials securely, restore valid credentials during app
  startup, refresh expired access tokens, re-fetch the HydraCam user GUID after
  restore, and clear both local app state and Auth0/browser session state on
  logout.
- Acceptance checks: after successful login, force-closing and reopening the app
  restores the same HydraCam user without another browser prompt; expired tokens
  refresh or fall back to a clear login-required state; logout prevents silent
  reuse of the previous user; no token is stored in plain shared preferences;
  `flutter analyze`, the relevant auth/unit tests, and Android plus iOS
  real-device or simulator smoke evidence are attached.
- 2026-06-08 refresh-scope note:
  `logs/verification-runs/20260608-1938-auth0-refresh-scope/` changes the
  Auth0 `AuthorizationTokenRequest` to use a shared
  `AuthService.authorizationScopes` list that includes `offline_access`, with a
  focused unit test plus screenshot/video proof. Keep this issue open for
  secure credential persistence, startup restore, token refresh, full logout
  clearing, and mobile smoke evidence.
- 2026-06-08 secure-credential-store note:
  `logs/verification-runs/20260608-2000-auth0-secure-credential-store/` adds an
  injectable Auth0 client plus `AuthCredentialStore`, persists returned access,
  ID, refresh-token, and expiration fields through a
  `FlutterSecureStorage`-backed default store after login, and proves the
  service contains no `shared_preferences` token storage. Keep this issue open
  for startup restore, token refresh, full logout clearing, HydraCam user GUID
  restore, and mobile smoke evidence.
- 2026-06-08 startup-restore note:
  `logs/verification-runs/20260608-2006-auth0-startup-restore-valid-credentials/`
  adds `AuthCredentialStore.load()` and `AuthService.restoreStoredSession()` so
  non-expired stored Auth0 credentials restore the access token, email, and
  profile picture without browser login, while expired credentials fall back to
  login-required state. Keep this issue open for refresh-token renewal, full
  logout clearing, HydraCam user GUID restore, and mobile smoke evidence.
- 2026-06-08 refresh-expired-credentials note:
  `logs/verification-runs/20260608-2011-20260608-2012-auth0-refresh-expired-credentials/`
  adds an injectable Auth0 refresh-token exchange and updates startup restore
  so expired stored access credentials refresh with the saved refresh token,
  persist renewed credential fields, and restore email/profile state when the
  refreshed token is valid. Keep this issue open for full logout clearing,
  HydraCam user GUID restore, and mobile smoke evidence.
- 2026-06-08 logout-clearing note:
  `logs/verification-runs/20260608-2017-auth0-logout-clears-credentials/`
  adds `AuthService.logout()`, secure credential clearing, Auth0 end-session
  invocation with the ID token, and wires `UserService.logout()` through the
  auth logout path while clearing local user state in a `finally` block. Keep
  this issue open for HydraCam user GUID restore and mobile smoke evidence.
- 2026-06-08 user-guid-restore note:
  `logs/verification-runs/20260608-2022-user-guid-restore-after-auth0-restore/`
  adds `UserService.restoreStoredSession()`, a test-only injection seam, and
  startup wiring in `main.dart` so restored Auth0 sessions re-fetch the
  HydraCam backend user GUID from the restored email before marking the app
  user logged in. Keep this issue open for Android plus iOS mobile smoke
  evidence.
- 2026-06-09 platform-boundary cleanup note:
  `logs/verification-runs/20260609-0426-auth0-mobile-platform-boundary-cleanup/`
  makes the old `AuthService` mobile-only TODO executable: unsupported desktop
  targets skip startup restore before reading credential storage and reject
  interactive login before invoking the AppAuth client. Existing Android/iOS
  login, restore, refresh, and logout unit coverage remains green. Keep this
  issue open for Android plus iOS mobile smoke evidence and Android
  process-death/account-switch validation.
- 2026-06-09 desktop-login message note:
  `logs/verification-runs/20260609-0432-login-desktop-auth0-message/` preserves
  the explicit mobile-only Auth0 error in `LoginScreen` instead of replacing it
  with the generic login failure text. Focused widget coverage proves desktop
  targets show `Auth0 interactive login is only supported on Android and iOS.`
  Keep this issue open for Android plus iOS mobile smoke evidence and Android
  process-death/account-switch validation.
- 2026-06-17 unsupported-logout credential cleanup note:
  focused `AuthService` unit coverage now proves unsupported desktop logout
  avoids the Auth0 browser end-session call while still clearing stored secure
  credentials and in-memory session state. Keep this issue open for Android plus
  iOS mobile smoke evidence and Android process-death/account-switch validation.
- 2026-06-17 missing-email restore cleanup note:
  focused `AuthService` unit coverage now proves stored Auth0 credentials with
  no email claim are rejected, cleared from secure storage, and removed from
  in-memory auth state before `UserService` can mark a HydraCam user restored.
  Keep this issue open for Android plus iOS mobile smoke evidence and Android
  process-death/account-switch validation.
- 2026-06-17 missing-email login cleanup note:
  focused `AuthService` unit coverage now proves interactive Auth0 login
  rejects returned ID tokens without an email claim, clears stale secure
  credentials, and leaves no in-memory access token or profile before the app
  can treat that Auth0 response as a HydraCam user. Keep this issue open for
  Android plus iOS mobile smoke evidence, Android process-death validation, and
  account-switch validation.
- 2026-06-17 failed-login stale-user cleanup note:
  focused `UserService` unit coverage now proves a failed second Auth0 login
  attempt clears the previously logged-in HydraCam email, profile picture, GUID,
  and logged-in state instead of leaving the prior account visible after the
  error. Keep this issue open for Android plus iOS mobile smoke evidence,
  Android process-death validation, and account-switch validation.
- 2026-06-17 expired-restore credential cleanup note:
  focused `AuthService` unit coverage now proves expired stored Auth0
  credentials are removed from secure storage when they cannot be restored
  directly, lack a refresh token, or refresh into unusable credentials. Keep this
  issue open for Android plus iOS mobile smoke evidence, Android process-death
  validation, and account-switch validation.
- 2026-06-17 malformed-token restore cleanup note:
  `logs/verification-runs/20260617-1933-auth0-malformed-id-token-restore-cleanup/`
  proves startup restore treats malformed stored Auth0 ID tokens as invalid
  credentials instead of throwing or preserving partial access-token state:
  secure credentials are cleared, in-memory auth state is empty, and restore
  returns the normal login-required result. Keep this issue open for Android
  plus iOS mobile smoke evidence, Android process-death validation, and
  account-switch validation.
- 2026-06-17 blank-email restore guard note:
  `logs/verification-runs/20260617-1938-user-restore-blank-email-guard/`
  proves `UserService.restoreStoredSession()` rejects a blank restored Auth0
  email before HydraCam GUID lookup, clears local user state, and avoids marking
  the app logged in from an empty identity. Keep this issue open for Android
  plus iOS mobile smoke evidence, Android process-death validation, and
  account-switch validation.
- 2026-06-17 blank-email login guard note:
  `logs/verification-runs/20260617-1941-user-login-blank-email-guard/` proves
  `UserService.login()` rejects a blank Auth0 email before HydraCam GUID lookup,
  clears local user state, and avoids marking the app logged in from an empty
  identity. Keep this issue open for Android plus iOS mobile smoke evidence,
  Android process-death validation, and account-switch validation.
- 2026-06-17 email-claim normalization note:
  `logs/verification-runs/20260617-1944-auth0-email-claim-normalization/`
  proves `AuthService` trims Auth0 email claims before exposing login or restored
  session state, so surrounding whitespace cannot leak into HydraCam GUID lookup
  or account display. Keep this issue open for Android plus iOS mobile smoke
  evidence, Android process-death validation, and account-switch validation.
- 2026-06-17 login-failure stale-session cleanup note:
  `logs/verification-runs/20260617-1947-auth0-login-failure-clears-stale-session/`
  proves a failed interactive Auth0 login clears stale secure credentials and
  in-memory Auth0 state instead of leaving the previous session available for
  silent reuse. Keep this issue open for Android plus iOS mobile smoke evidence,
  Android process-death validation, and account-switch validation.
- 2026-06-17 blank stored token guard note:
  `logs/verification-runs/20260617-1949-auth0-blank-stored-token-guards/`
  proves startup restore rejects whitespace-only stored access tokens and does
  not attempt token refresh with a whitespace-only refresh token. Keep this
  issue open for Android plus iOS mobile smoke evidence, Android process-death
  validation, and account-switch validation.
- 2026-06-18 auth runtime recoverability rollup:
  `logs/verification-runs/20260618-1321-auth0-runtime-recoverability/` reran
  the focused Auth0, UserService, startup widget, and LoginScreen coverage plus
  `flutter analyze --no-pub` after the session-model cleanup landed. The local
  contract now covers malformed/missing/blank identity rejection, stale
  credential cleanup, blank-email GUID lookup guards, desktop logout cleanup,
  and non-blocking backend warm-up. Keep this issue open for Android plus iOS
  mobile smoke evidence, Android process-death validation, and account-switch
  validation.

### 12. Decide and implement Android-native account-picker sign-in

- Source: current Android UX gap, 2026-06-07; users expect the local Android
  account/credential sheet seen in other apps, but the current `flutter_appauth`
  path launches Auth0 Universal Login in a browser or Chrome Custom Tab.
- Labels: `hydracam`, `mobile`, `auth`, `android`, `ux`, `external-backend`.
- Priority: Medium.
- Body: Decide whether HydraCam should keep Auth0 Universal Login only, migrate
  mobile auth to `auth0_flutter` with its Credentials Manager, or add Android
  Credential Manager / Sign in with Google for a native account-picker path. If
  native Android sign-in is selected, define how the returned Google/credential
  identity maps into Auth0 and the HydraCam backend user GUID.
- Acceptance checks: decision record compares Auth0 Universal Login,
  `auth0_flutter` Credentials Manager, and Android Credential Manager / Sign in
  with Google; selected path is implemented behind a clear service interface;
  Android shows the expected native credential/account sheet when applicable;
  backend/Auth0 user linking is proven for an existing Android user's account;
  logout and account switching are tested on a real Android device; privacy/data
  safety notes are updated if additional identity data is collected.
- 2026-06-17 decision note:
  `docs/control/android-auth-sign-in-decision.md` compares the current
  `flutter_appauth` path, `auth0_flutter`, and Android Credential Manager /
  Sign in with Google. The current release-lane decision is to keep Auth0
  Universal Login behind the existing `AuthService` abstraction and defer native
  Credential Manager until backend/Auth0 account linking is specified. Keep this
  issue open only if product explicitly reopens native Android account-picker
  implementation; mobile login smoke and account-switch proof remain tracked by
  issue 11.

### 13. Desktop/webcam scope decision completed

- Sources: `JAVI IMMEDIATE BACKLOG` rows 76, 83, 103.
- Labels: `hydracam`, `mobile`, `desktop`, `webcam`.
- Priority: Low.
- Disposition: Completed in `docs/control/status-and-roadmap.md` on 2026-06-06.
- Decision: desktop is monitoring/development-only for now; webcam capture is
  deferred. Do not create a live Linear issue for generic webcam capture unless
  the scope is reopened with a concrete workflow.

### 14. Add mobile preview streams on master

- Sources: `SYSTEM FEATURES` F18; FR-045, FR-046; `Testing table` T-021, T-022.
- Labels: `hydracam`, `mobile`, `preview`, `external-backend`.
- Priority: Medium.
- Body: Display preview streams or still frames from slaves on the master.
  Requires a design for transport and resource usage.
- Acceptance checks: preview contract is documented, master UI handles missing
  previews, and bandwidth/latency constraints are tested before broad rollout.
- 2026-06-08 missing-preview-state note:
  `logs/verification-runs/20260608-2105-master-slave-preview-missing-state/`
  adds explicit missing-preview status fields to connected-client diagnostics
  and shows `Preview unavailable (Preview transport not configured)` in the
  master known-device modal. Keep this issue open for actual preview transport
  design, bandwidth limits, and real multi-device preview evidence.
- 2026-06-17 disconnected-preview-state note:
  focused `ConnectedDeviceInfo` and automation-payload coverage now separates
  disconnected slave preview state from missing transport: stale rows report
  `Preview unavailable: disconnected (Slave disconnected)` instead of implying
  the only blocker is unconfigured preview transport. Keep this issue open for
  actual preview transport design, bandwidth limits, and real multi-device
  preview evidence.
- 2026-06-17 stale-setup-readiness note:
  focused connected-client automation coverage now exposes `setupStatusLabel`
  and labels disconnected slave setup state as historical, for example
  `Last reported setup: Right back glass | Level`. The master known-device
  modal uses the same label so placement/leveling readiness is not presented as
  live after a slave disconnects. Keep this issue open for actual preview
  transport design, bandwidth limits, and real multi-device preview evidence.

### 15. Add consistent club and court photos to venue selection

- Source: product idea, 2026-06-17.
- Labels: `hydracam`, `mobile`, `ux`, `venues`, `courts`, `visual-assets`.
- Priority: Medium.
- Disposition: Planned only; do not implement until the image source, backend
  contract, and asset-quality standard are decided.
- Body: Support sports center and court selection with a consistent set of
  high-quality pictures for each club and each court. The pictures should help
  operators visually confirm they picked the right venue/court before creating
  a capture session, especially in clubs with similar court names or repeated
  numbered courts. This is selection support, not a gallery or marketing
  feature.
- Implementation plan:
  1. Define the asset standard: required shots per club and court, aspect
     ratio, minimum resolution, lighting/framing rules, naming convention,
     review owner, and fallback policy when a venue lacks approved photos.
  2. Decide the source of truth: extend the sports center/court API contract
     with stable image URLs and metadata, or ship a temporary local asset
     manifest only for approved pilot clubs.
  3. Add data models and caching: parse club/court image metadata, cache
     thumbnails safely for offline or weak-network setup, and keep missing or
     stale images explicit in diagnostics/logging.
  4. Update `SportsCentersScreen` and `CourtsScreen`: show compact thumbnails
     or photo-backed rows/cards that preserve fast scanning, visible selected
     state, court name/location text, and accessible labels.
  5. Add validation: focused widget tests for image/fallback/selection states,
     a no-overflow route smoke on phone-sized viewports, and a real-device UI
     screenshot pack before marking the feature complete.
- Acceptance checks: every returned sports center and court either shows an
  approved photo or a clear non-photo fallback; visual treatment is consistent
  across clubs/courts; selection remains unambiguous from text plus selected
  state; missing/slow images do not block venue selection or session creation;
  photos have accessible labels; focused widget tests and `flutter analyze`
  pass; hardware UI screenshots prove the selection routes render without
  overflow on at least one supported Android device and one iOS target when
  available.
- Non-goals: do not change session creation, court GUID handling, upload
  behavior, or master/slave capture flow as part of this item. Do not add
  unsourced stock imagery or one-off decorative backgrounds.

## Open Bug/Improvement Rows From `FALLOS Y MEJORAS`

These are de-duplicated open rows from the Spanish and English tabs. Create
separate issues only when the grouped candidates above do not already cover the
work.

| Row | Type | Title | Labels | Suggested disposition |
| ---: | --- | --- | --- | --- |
| 7 | Mejora | Master UI rebuild/flicker | `hydracam`, `mobile`, `ux` | Issue if still reproducible. |
| 8 | Mejora | Detect devices connected to another session | `hydracam`, `mobile`, `session` | Merge with session integrity work. |
| 13 | Mejora | Improve device dropdown | `hydracam`, `mobile`, `network`, `ux` | Merge with network/device identity issue. |
| 17 | Fallo | Video duration still wrong at 357 seconds | `hydracam`, `mobile`, `upload`, `external-backend` | Backend dependency plus mobile metadata verification. |
| 22 | Fallo | Reset session on reconnect | `hydracam`, `mobile`, `session` | Priority issue. |
| 23 | Mejora | Upload failure UI | `hydracam`, `mobile`, `upload` | Merge with upload UI issue. |
| 24 | Fallo | Photo missing on old slave device | `hydracam`, `mobile`, `camera`, `android` | Issue if reproducible on target legacy device. |
| 25 | Mejora | Cancel upload | `hydracam`, `mobile`, `upload` | Merge with upload UI issue. |
| 26 | Fallo | iOS role-selection back arrow with nowhere to go | `hydracam`, `mobile`, `ios`, `ux` | Issue if still visible. |
| 27 | Fallo | iOS client/network behavior as slave/master | `hydracam`, `mobile`, `ios`, `network` | Merge with iOS reliability. |
| 30 | Fallo | iOS disconnects as slave in under 10 seconds | `hydracam`, `mobile`, `ios`, `websocket` | Merge with iOS reliability. |
| 31 | Fallo | iPad camera does not save photos | `hydracam`, `mobile`, `ios`, `camera` | Fixed in `logs/verification-runs/20260606-2310-ipad-capture-failure-trace-and-repro/`; keep regression coverage. |
| 32 | Mejora | Old media should not require a specific filter | `hydracam`, `mobile`, `gallery` | Merge with gallery session attachment. |
| 33 | Fallo | iPhone/iPad auto-connect from mode selection but do not advance | `hydracam`, `mobile`, `ios`, `navigation` | Issue only if still reproducible after the 2026-06-06 iPhone/iPad working evidence. |
| 34 | Mejora | Investigate Android 4.1.2 legacy support | `hydracam`, `mobile`, `android` | Defer unless product values legacy devices. |
| 35 | Novedad | Add players mid session | `hydracam`, `mobile`, `users` | Merge with user/player assignment. |
| 36 | Fallo | Null check error stopping recording on macOS/iPad | `hydracam`, `mobile`, `recording`, `desktop`, `ios` | Issue if still reproducible. |
| 40 | Novedad | Know/change main storage vs SD | `hydracam`, `mobile`, `storage`, `android` | Defer behind Android storage strategy. |
| 41 | Novedad | Multiple camera groups on same local network | `hydracam`, `mobile`, `network` | Future feature; group with network identity. |
| 42 | Novedad | Keep app in foreground / prevent backgrounding | `hydracam`, `mobile`, `recording`, `android`, `ios` | Issue after platform policy review. |
| 43 | Novedad | Time corrections / NTP | `hydracam`, `mobile`, `sync` | Priority issue. |
| 44 | Novedad | Find videos that fit previous session timeline | `hydracam`, `mobile`, `gallery`, `session` | Merge with gallery session attachment. |
| 45 | Novedad | Locate videos closer than configured split time | `hydracam`, `mobile`, `gallery`, `session` | Merge with gallery session attachment. |
| 46 | Novedad | Add videos matching session date with margin | `hydracam`, `mobile`, `gallery`, `session` | Merge with gallery session attachment. |
| 47 | Novedad | Master asks slaves whether alive via flash/frame | `hydracam`, `mobile`, `websocket`, `diagnostics` | Issue after network/device identity work. |

2026-06-08 row 17 note:
`logs/verification-runs/20260608-2145-video-upload-duration-metadata/` adds
mobile-side video timing metadata to multipart uploads: `recordingEndDate` and
`durationMs` are included for videos while photo uploads remain unchanged.
Keep row 17 open for backend/API contract confirmation and proof that MoBo no
longer displays the 357-second duration incorrectly.

2026-06-17 row 17 timestamp-derived duration note:
focused upload API coverage now proves `durationMs` is derived from
`recordingEndDate - captureDate` when those timestamps are present, even if a
caller supplies a conflicting `recordingDuration`. This keeps mobile multipart
video timing fields internally consistent before backend duration calculation.
Keep row 17 open for backend/API contract confirmation and proof that MoBo no
longer displays the 357-second duration incorrectly.

2026-06-17 row 17 inverted-duration guard note:
focused upload API coverage now rejects video uploads whose recording end
timestamp is earlier than the capture/start timestamp, logs the invalid
duration before token/header setup, and avoids sending a multipart request with
a negative `durationMs`.
Keep row 17 open for backend/API contract confirmation and proof that MoBo no
longer displays the 357-second duration incorrectly.

2026-06-17 row 26 regression note:
`RoleSelectionScreen` already disables the visual back affordance and blocks
route-root popping through `PopScope(canPop: false)`. Focused widget coverage
now proves there is no back arrow on the entry surface and that a system back
route leaves the role-selection screen mounted. Treat row 26 as locally covered
unless a fresh physical iOS reproduction shows a different navigation path.

2026-06-08 row 36 note:
`logs/verification-runs/20260608-2125-forced-stop-missing-start-timestamp/`
adds a forced-stop video metadata fallback so critical battery/storage stops
record media even when the camera start timestamp is missing, using the end
timestamp as a safe fallback instead of throwing a null-check error. Keep row
36 open only for real macOS/iPad reproduction proof if it recurs.

2026-06-08 row 40 note:
`logs/verification-runs/20260608-2155-storage-location-missing-state/` adds a
read-only `Storage location` row to Settings that reports `Internal app
storage` and `SD card selection not configured`. Keep row 40 open for the
actual Android storage strategy, SD-card selection, and real-device storage
proof.

2026-06-08 row 47 note:
`logs/verification-runs/20260608-2135-slave-identify-diagnostic-ack/` adds a
targeted `identifySlave` diagnostic command and `identifyAck` slave response so
the master can ask a selected connected slave to prove it is alive and expose
the acknowledgement in connected-device diagnostics. Keep row 47 open for
actual flash/frame identification behavior and real multi-device diagnostic
proof.

2026-06-09 targeted-command-dispatch cleanup:
`logs/verification-runs/20260609-0214-master-targeted-command-dispatch-cleanup/`
unifies `sendCommandToAll` and `sendCommand` around one eligible-client
dispatcher and proves that a command with a missing non-null slave ID no longer
falls back to broadcast. Keep row 47 open for actual flash/frame identification
behavior and real multi-device diagnostic proof.

2026-06-09 scheduled-command-dispatch cleanup:
`logs/verification-runs/20260609-0219-master-scheduled-command-dispatch-cleanup/`
extends the same dispatcher to `scheduleCommand` and proves that a scheduled
command with a missing non-null slave ID no longer falls back to broadcast.
Keep row 47 open for actual flash/frame identification behavior and real
multi-device diagnostic proof.

2026-06-09 master incoming-message handler cleanup:
`logs/verification-runs/20260609-0256-master-server-incoming-message-handler-cleanup/`
extracts incoming WebSocket message handling out of `MasterServer.startServer()`
into a testable handler and proves a slave `deviceId` registration still stores
the connected device and sends the current session-status response. Keep row 47
open for actual flash/frame identification behavior and real multi-device
diagnostic proof.

2026-06-09 master unused session-history cleanup:
`logs/verification-runs/20260609-0330-master-server-unused-session-history-cleanup/`
removes the obsolete `MasterServer.sessionHistory` field and its now-unused
`CaptureSession` import after session state had already moved to
`SessionManager`. Keep row 47 open for actual flash/frame identification
behavior and real multi-device diagnostic proof.

2026-06-09 received-media storage helper cleanup:
`logs/verification-runs/20260609-0344-master-received-media-storage-helper-cleanup/`
extracts received media directory creation, filename generation, byte writes,
and gallery persistence dispatch from `MasterServer._saveMediaLocally()` into
`SessionMediaStorage`. Focused service tests prove photo/video path and gallery
dispatch behavior, and a MasterServer regression proves incoming slave photo
media is saved through the helper and registered in the active session.
`logs/verification-runs/20260609-0437-received-media-declared-type-extension-cleanup/`
then switches extension selection to the declared media type so video messages
cannot be saved with a `.jpg` path just because their first byte is `0xFF`.
Keep row 47 open for actual flash/frame identification behavior and real
multi-device diagnostic proof.

2026-06-09 slave identify visible-frame note:
`logs/verification-runs/20260609-0445-slave-identify-visible-frame/` turns the
slave-side `identifyAck` status into a temporary visible frame labeled
`Identifying this slave`, clears the frame after the identify window, and wakes
the quiet/dimmed slave screen so the targeted device can be found visually.
Focused widget coverage proves the frame appears from the identify
acknowledgement status and then clears without changing the network command or
ACK contract. Keep row 47 open for real multi-device diagnostic proof and any
future hardware-flash behavior if product wants more than the on-screen frame.

## Open Rows From `JAVI IMMEDIATE BACKLOG`

| Row | User story | Labels | Suggested disposition |
| ---: | --- | --- | --- |
| 29 | Localizar todo | `hydracam`, `mobile`, `location` | Clarify before issue creation. |
| 35 | Use GUIDs everywhere across controllers/views | `hydracam`, `mobile`, `session` | Issue if code audit finds inconsistent IDs. |
| 68 | Editable setting for auto-record mode | `hydracam`, `mobile`, `unattended` | Merge with auto-record issue. |
| 71 | Auto-record starts recording when slave connects to active master session | `hydracam`, `mobile`, `unattended`, `recording` | Merge with auto-record issue. |
| 76 | Use webcam(s) | `hydracam`, `mobile`, `desktop`, `webcam` | Completed by desktop/webcam scope decision; deferred. |
| 81 | Add DSQV German players | `hydracam`, `mobile`, `users` | Merge with user/player assignment. |
| 82 | Auto-record mode | `hydracam`, `mobile`, `unattended` | Merge with auto-record issue. |
| 83 | Use webcam from PC | `hydracam`, `desktop`, `webcam` | Completed by desktop/webcam scope decision; deferred. |
| 84 | Access old sessions and add/delete gallery videos | `hydracam`, `mobile`, `gallery`, `session` | Merge with gallery session attachment. |
| 85 | Users access web app with QR to request recording | `hydracam`, `mobile`, `external-backend`, `unattended` | Backend/web dependency. |
| 88 | Camera quality setting | `hydracam`, `mobile`, `camera` | Verified complete in `SettingsScreen`, `SettingsService`, and `CameraServiceSingleton` on 2026-06-06. |
| 89 | Camera selector setting | `hydracam`, `mobile`, `camera` | Verified complete in `CameraSelectionScreen` and `CameraServiceSingleton` on 2026-06-06. |
| 96 | Explicit resolution for high/medium/low | `hydracam`, `mobile`, `camera` | Completed on 2026-06-06 by clarifying that quality choices map to device-dependent Flutter camera presets. |
| 100 | Fix user assignment from backend | `hydracam`, `mobile`, `users`, `external-backend` | Backend dependency. |
| 102 | Calculate upload time from bytes uploaded | `hydracam`, `mobile`, `upload` | Merge with upload UI issue. |
| 103 | Windows version | `hydracam`, `desktop` | Completed by desktop/webcam scope decision; monitor/control only for now. |
| 105 | MoBo video gallery too slow for heavy videos | `hydracam`, `external-backend`, `media` | Backend/web dependency unless mobile view affected. |
| 106 | Hardcoded fields when uploading photos/videos | `hydracam`, `mobile`, `upload`, `external-backend` | Contract issue; coordinate with backend. |
| 109 | Load squash-liga rankings | `hydracam`, `mobile`, `users` | Product/data import task; defer. |
| 111 | Uploaded material includes app version | `hydracam`, `mobile`, `upload` | Include with upload metadata issue. |
| 113 | Send "start uploading all" message | `hydracam`, `mobile`, `upload`, `websocket` | Merge with upload controls issue. |
| 114 | Access upload info from slaves | `hydracam`, `mobile`, `upload`, `websocket` | Merge with upload controls issue. |
| 115 | Show which network is active | `hydracam`, `mobile`, `network` | Merge with network/device identity issue. |
| 119 | Autostop video on critical battery | `hydracam`, `mobile`, `battery`, `recording` | Priority issue. |

2026-06-08 row 35 note:
`logs/verification-runs/20260608-2215-gallery-candidate-guid-label/` changes
old-media candidate labels in `MediaSelectionScreen` to prefer `sessionGuid`
and fall back to `sessionId` only when no GUID is available. Keep row 35 open
for a broader controllers/views GUID audit and real old-media attachment smoke
evidence.

2026-06-09 row 35 cleanup note:
`logs/verification-runs/20260609-0140-guid-api-upload-estimate-cleanup/`
adds a shared `CaptureSession.preferredIdentifier`, routes old-media candidate
labels and candidate-source dedupe through it, and updates
`SessionDetailsScreen` title/load actions to prefer `sessionGuid` while
falling back to `sessionId` for legacy metadata without a null-check failure.
Keep row 35 open for real old-media attachment smoke evidence and any broader
controller/view GUID audit not covered by these local widget/model tests.

2026-06-09 row 35 restore-helper cleanup note:
`logs/verification-runs/20260609-0145-session-restore-helper-cleanup/`
extracts duplicated previous-session restore logic from `SessionDetailsScreen`
into `SessionManager.restoreSessionFromMetadata()`, proving the shared path
starts the preferred identifier, keeps the caller-selected role, and re-queues
loaded photos/videos exactly once. Keep row 35 open for real old-media
attachment smoke evidence and any broader controller/view GUID audit not covered
by these local unit/widget tests.

2026-06-09 row 35 details-metadata cleanup note:
`logs/verification-runs/20260609-0451-session-details-guid-primary-metadata/`
changes `SessionDetailsScreen` metadata to use
`CaptureSession.preferredIdentifier` as the primary session reference and labels
the legacy `sessionId` only as `Legacy Session ID` when a backend GUID exists.
Focused widget coverage proves the details screen shows the backend GUID in both
the app bar and metadata panel, while no longer presenting the legacy ID as the
primary session identifier. Keep row 35 open for real old-media attachment smoke
evidence and any remaining controller/view GUID audit not covered by local
widget/model tests.

2026-06-09 row 35 sessions-list cleanup note:
`logs/verification-runs/20260609-0459-sessions-list-guid-primary-display/`
changes `SessionsScreen` to use the backend `guid` as the primary session
reference in the backend session list and load feedback, while labeling a
distinct `sessionId` only as `Legacy Session ID`. Focused widget coverage proves
the fetched sessions list displays `Session: <guid>`, keeps the legacy ID out of
the primary title, and joins the backend GUID when the download/load action is
selected. Keep row 35 open for real old-media attachment smoke evidence and any
remaining controller/view GUID audit not covered by local widget/model tests.

2026-06-09 row 35 session-directory scan cleanup note:
`logs/verification-runs/20260609-0506-session-directory-identifier-scan-cleanup/`
unifies `SessionManager` previous-session directory identifier extraction so
`getAvailableSessions()` and `scanAndReconstructSessions()` both strip only the
leading `session_` prefix. Focused service coverage first reproduced truncation
of `session_scan_preserve_full_guid` to `guid`, then passed with reconstruction
preserving the full identifier and writing metadata back under the original
directory. Keep row 35 open for real old-media attachment smoke evidence and any
remaining controller/view GUID audit not covered by local widget/model tests.

2026-06-17 row 35 cleaned-media metadata note:
focused `SessionManager` and media-model coverage now proves previous-session
metadata can be loaded after local photo/video files have been cleaned up, while
persisting and restoring `fileSizeInBytes` from metadata instead of requiring
the path to still exist. Keep row 35 open for real old-media attachment smoke
evidence and any remaining controller/view GUID audit not covered by local
widget/model tests.

2026-06-17 row 35 uploaded-restore queue note:
focused `SessionManager` coverage now proves restoring historical metadata does
not requeue photo/video records that are already marked uploaded; the uploader
boundary logs already-uploaded media as a no-op instead of duplicating upload
work. Keep row 35 open for real old-media attachment smoke evidence and any
remaining controller/view GUID audit not covered by local widget/model tests.

2026-06-18 row 35 stored-media GUID-primary note:
`logs/verification-runs/20260618-1508-stored-media-guid-primary-display/`
changes `PreviousSessionsScreen` stored-media rows to load metadata snapshots,
display `CaptureSession.preferredIdentifier` as `Session: <guid>`, label a
distinct legacy ID separately, and pass the original storage directory
identifier into `SessionDetailsScreen` so restore still works when metadata GUID
differs from the folder key. Focused widget coverage proves GUID-primary display
and storage-key restore, and the full Flutter analyzer/test suite passed. Keep
row 35 open for real old-media attachment smoke evidence and any remaining
controller/view GUID audit not covered by local widget/model tests.

2026-06-18 row 35 storage-key naming audit note:
`logs/verification-runs/20260618-1531-stored-session-guid-storage-key-audit/`
adds gallery candidate coverage for loading metadata by a local storage
directory key while preserving the backend `sessionGuid`, then renames ambiguous
previous-session controller/source locals from `sessionId` to
`storageIdentifier` where they refer to folder keys. Focused previous-session,
gallery candidate-source, and session-manager tests passed, as did full analyzer
and full Flutter tests. Keep row 35 open for real old-media attachment smoke
evidence and any remaining controller/view GUID audit not covered by local
widget/model tests.

2026-06-18 row 35 blank stored-GUID restore note:
`logs/verification-runs/20260618-1540-blank-stored-session-guid-restore/`
adds regressions for stored metadata with a blank or whitespace-only
`sessionGuid`. Previous-session restore now repairs blank stored GUIDs from the
service storage directory key before restoring and re-queueing media, and
`CaptureSession.preferredIdentifier` trims GUIDs before deciding whether to fall
back to the legacy `sessionId`. Focused restore/display/candidate tests, full
analyzer, and full Flutter tests passed. Keep row 35 open for real old-media
attachment smoke evidence and any remaining controller/view GUID audit not
covered by local widget/model tests.

2026-06-08 row 111 note:
`logs/verification-runs/20260608-1901-upload-app-version-metadata/` adds
`appVersion` and `appBuildNumber` multipart fields to media uploads and proves
the contract with a focused mock-HTTP service test plus screenshot/video proof.

2026-06-08 row 106 note:
`logs/verification-runs/20260608-2127-upload-media-contract-fields/`
centralizes the mobile upload-media endpoint, query keys, multipart field
names, file field, method, and success status in
`HydraCamUploadMediaContract`, and proves `uploadMedia()` still sends the same
photo/video payload contract through focused tests plus screenshot/video
evidence. Keep row 106 open for backend/API contract coordination and any
server-side hardcoded field cleanup.

2026-06-09 row 106 cleanup note:
`logs/verification-runs/20260609-0140-guid-api-upload-estimate-cleanup/`
centralizes the mobile user lookup endpoint and email query key in
`HydraCamUserContract`, routes user-details lookup through a shared endpoint
helper, removes the dead hardcoded `UserService` user API URL, and proves the
email lookup preserves encoded addresses such as `player+one@example.com`.
Keep row 106 open for backend/API contract coordination and server-side
hardcoded field cleanup.

2026-06-09 row 106 URI cleanup note:
`logs/verification-runs/20260609-0151-api-uri-construction-cleanup/`
centralizes mobile API endpoint/query construction with `hydracamApiEndpoint()`
and the service base-URI join helper, removing whitespace-stripping URI
concatenation from GET/POST/session/upload/user paths. Focused mock-HTTP tests
prove `fetchCourts()` and `endSession()` preserve spaces, slashes, and literal
`+` characters in query values. Keep row 106 open for backend/API contract
coordination and server-side hardcoded field cleanup.

## Testing Issue Candidates

The sheet had 23 open tests. Use these as test backlog seeds, not as proof that
the repo lacks all coverage.

| Source tests | Candidate | Labels |
| --- | --- | --- |
| T-017, T-018 | Mobile recording start/stop and upload regression tests | `hydracam`, `mobile`, `testing`, `recording`, `upload` |
| T-019 | Time synchronization accuracy test | `hydracam`, `mobile`, `testing`, `sync` |
| T-020 | Upload time estimate test | `hydracam`, `mobile`, `testing`, `upload` |
| T-021, T-022 | Readiness and preview-stream tests | `hydracam`, `mobile`, `testing`, `preview`, `websocket` |
| T-001 | Auth0 login, startup restore, Android process-death recovery, logout, and account-switch regression tests | `hydracam`, `mobile`, `testing`, `auth`, `android`, `ios` |
| T-016 | Photo/video upload API test with invalid files | `hydracam`, `mobile`, `testing`, `upload`, `external-backend` |

2026-06-08 T-016 note:
`logs/verification-runs/20260608-2205-invalid-upload-file-guard/` adds an
invalid-file upload guard so `HydraCamApiService.uploadMedia()` returns false,
logs `Upload file does not exist`, and avoids sending a multipart HTTP request
when the local media file is missing. Keep broader invalid-file/API contract
coverage open for backend response-shape and corrupt-file cases.

2026-06-09 T-016 empty-file guard note:
`logs/verification-runs/20260609-0430-upload-empty-file-guard/` adds a
zero-byte media guard so `HydraCamApiService.uploadMedia()` returns false, logs
`Upload file is empty`, and avoids sending a multipart HTTP request when a
capture path exists but contains no bytes. Keep broader invalid-file/API
contract coverage open for backend response-shape and corrupt-file cases beyond
zero-byte local media.

2026-06-09 T-016 backend-response guard note:
`logs/verification-runs/20260609-0435-upload-backend-failure-response-guard/`
adds local response-shape coverage so `HydraCamApiService.uploadMedia()` no
longer treats every HTTP 200 as success when the backend body explicitly reports
failure through fields such as `success: false` or failure/error status values.
Empty 200 bodies remain accepted for the current backend-compatible success
path. Keep broader invalid-file/API contract coverage open for true corrupt
media handling and live backend response-shape confirmation.

2026-06-17 T-016 malformed-response guard note:
focused upload API coverage now rejects non-empty malformed HTTP 200 bodies
instead of treating them as successful uploads. Empty 200 bodies remain accepted
for the current backend-compatible path, and valid object bodies still fail only
when they explicitly report failure. Keep broader invalid-file/API contract
coverage open for true corrupt media handling and live backend response-shape
confirmation.

2026-06-17 T-016 corrupt-local-media guard note:
focused upload API coverage now rejects obvious corrupt local media before HTTP
send by checking photo/video file signatures. JPEG/PNG/HEIC-style photo inputs
and MP4/MOV-style video inputs remain accepted, while invalid bytes in `.jpg`
and `.mp4` paths return false, log the specific invalid media type, and avoid
building multipart requests. Keep broader contract coverage open for live
backend response-shape confirmation and any camera-plugin format added later.

2026-06-17 T-016 backend-error response note:
focused upload API coverage now treats non-empty `error` or `errors` fields in
HTTP 200 upload responses as failed uploads, matching the existing
`success: false`, failed `status`, and malformed-body guards. Keep broader
contract coverage open for live backend response-shape confirmation and any
camera-plugin format added later.

2026-06-18 T-016 textual-success response note:
`logs/verification-runs/20260618-1512-upload-textual-false-response-guard/`
extends upload response-shape handling so boolean-like text/numeric success
aliases are parsed before accepting HTTP 200 uploads. Focused coverage now
rejects `success: "false"`, `succeeded: "0"`, and `isSuccess: "no"` response
bodies instead of logging them as successful uploads. Keep broader contract
coverage open for live backend response-shape confirmation and any
camera-plugin format added later.

2026-06-18 T-016 ISO brand signature note:
`logs/verification-runs/20260618-1516-upload-iso-brand-signature-guard/`
tightens ISO BMFF media validation so an `ftyp` marker is not enough to pass
local upload guards. Video uploads now require an accepted video major brand,
photo uploads require an accepted HEIC/HEIF-style major brand, forged
`ftypbad!` media is rejected before token lookup/HTTP send, and HEIC photo
coverage proves iOS-style photo uploads still pass. Keep broader contract
coverage open for live backend response-shape confirmation and any
camera-plugin format added later.

2026-06-08 T-017 note:
`logs/verification-runs/20260608-2140-storage-critical-block-recovery/` fixes
`StorageService` so recording remains blocked only while available storage is
below the critical threshold; recovery above critical clears the block even if
storage is still below the low-warning threshold. Keep production closure gated
on real-device storage-pressure recording proof.

2026-06-08 T-018 note:
`logs/verification-runs/20260608-2132-in-flight-upload-dedupe/` adds an
in-flight duplicate retry guard so `UploaderService.addMediaToQueue()` refuses
to enqueue media whose `mediaPath` is already the current upload, logs `Media
already uploading`, and keeps the queue length unchanged. Keep broader mobile
upload path closure gated on real-device/backend upload smoke evidence.

2026-06-09 T-018 async enqueue cleanup note:
`logs/verification-runs/20260609-0223-uploader-enqueue-async-return-cleanup/`
changes `UploaderService.addMediaToQueue()` from hidden `async void` to an
awaitable `Future<void>` so tests and retry callers can wait through the
settings-driven enqueue branch. Existing queued-media and current-upload
duplicate guards remain covered by focused uploader tests. Keep broader mobile
upload path closure gated on real-device/backend upload smoke evidence.

2026-06-09 T-018 manual upload cleanup note:
`logs/verification-runs/20260609-0245-uploader-manual-upload-future-cleanup/`
changes `UploaderService.startUploadingManually()` and the internal upload
drain path to return `Future<void>` so tests and command/UI callers can await
manual upload completion instead of polling queue side effects. Auto-upload
remains fire-and-forget, while focused uploader, slave-command, uploader-info,
and session-details tests plus full repo gates pass. Keep broader mobile upload
path closure gated on real-device/backend upload smoke evidence.

2026-06-09 T-018 slave command dispatch cleanup note:
`logs/verification-runs/20260609-0252-slave-command-future-dispatch-cleanup/`
changes `SlaveClient` command dispatch so immediate JSON/raw commands await
their async handlers instead of dropping returned `Future`s. Scheduled commands
still execute at their scheduled time through `ScheduledTaskService`. Focused
slave-command, slave-screen, and scheduled-task tests plus full repo gates pass.
Keep broader mobile upload path closure gated on real-device/backend upload
smoke evidence.

2026-06-17 T-018 missing-file queue failure note:
focused `UploaderService` coverage now proves a media file that disappears after
queueing but before manual upload is marked with `Upload failed: file does not
exist on disk.`, persisted into `metadata.json`, clears the active uploader
state, and lets the queue drain. Keep broader mobile upload path closure gated
on real-device/backend upload smoke evidence.

2026-06-08 T-020 note:
`logs/verification-runs/20260608-2136-uploader-estimate-completed-samples/`
records completed upload samples in `UploaderService`, recalculates estimates
when later media is queued, and proves a 100-byte upload completed in 5 seconds
produces a 10-second estimate for a 200-byte queued item. Keep production
closure gated on real upload telemetry across device/backend conditions.

2026-06-09 T-020 cleanup note:
`logs/verification-runs/20260609-0140-guid-api-upload-estimate-cleanup/`
refines the estimator to use fractional seconds instead of truncating completed
upload samples to whole seconds, so a 100-byte upload completed in 500 ms
produces a 1-second estimate for a 200-byte queued item. Keep production
closure gated on real upload telemetry across device/backend conditions.

2026-06-08 T-001 note:
`logs/verification-runs/20260608-2144-user-login-clears-stale-guid/` fixes
`UserService.login()` so a new Auth0 login clears prior HydraCam GUID and
logged-in state before mapping the email, and an unmapped backend email clears
email, profile picture, GUID, and login state instead of reusing the previous
account. Keep production closure gated on Android/iOS Auth0 account-switch
smoke evidence.

Backend-only tests from T-002 through T-015 and T-023 should be moved to the
backend/web tracker unless a mobile mock/integration harness is explicitly in
scope.
