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
  records the latest matrix after automation batching, local session-end, and
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

### 2. Preserve session state across master reconnect

- Source: `FALLOS Y MEJORAS` row 22 / `(EN)` row 10.
- Original: "reset session on reconnect" after disconnecting master and
  returning to master screen, slave still shows session but loses materials.
- Labels: `hydracam`, `mobile`, `session`, `websocket`.
- Priority: High.
- Acceptance checks: reconnecting to the same active session does not clear
  captured media, metadata remains consistent on master and slave, and a test or
  reproducible manual script covers the flow.

### 3. Prevent stale uploads from crossing sessions

- Source: `FALLOS Y MEJORAS` row 2, completed in sheet but important enough to
  keep as regression protection.
- Labels: `hydracam`, `mobile`, `upload`, `session`, `testing`.
- Priority: High.
- Acceptance checks: ending a session before uploads finish cannot attach media
  to the next session; uploader queue reset behavior is covered by test or
  manual validation.

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

### 5. Add critical battery autostop

- Sources: `JAVI IMMEDIATE BACKLOG` row 119; `FALLOS Y MEJORAS` row 38.
- Labels: `hydracam`, `mobile`, `battery`, `recording`.
- Priority: High.
- Acceptance checks: when battery becomes critical during recording, recording
  stops safely, user sees a meaningful message, logs are written through
  `LogService`, and non-critical low-battery warnings are throttled.

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

### 8. Implement autograbado mode

- Sources: `JAVI IMMEDIATE BACKLOG` rows 68, 71, 82; sprint future rows 20-21.
- Labels: `hydracam`, `mobile`, `session`, `recording`, `unattended`.
- Priority: Medium.
- Body: Add a setting for autograbado/unattended mode so devices start
  recording automatically when slaves connect to a master with an active
  session.
- Acceptance checks: setting is editable, disabled by default unless product
  decides otherwise, auto-start happens only under clear active-session
  conditions, and users can stop recording safely.

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

## Open Rows From `JAVI IMMEDIATE BACKLOG`

| Row | User story | Labels | Suggested disposition |
| ---: | --- | --- | --- |
| 29 | Localizar todo | `hydracam`, `mobile`, `location` | Clarify before issue creation. |
| 35 | Use GUIDs everywhere across controllers/views | `hydracam`, `mobile`, `session` | Issue if code audit finds inconsistent IDs. |
| 68 | Editable setting for autograbado mode | `hydracam`, `mobile`, `unattended` | Merge with autograbado issue. |
| 71 | Autograbado starts recording when slave connects to active master session | `hydracam`, `mobile`, `unattended`, `recording` | Merge with autograbado issue. |
| 76 | Use webcam(s) | `hydracam`, `mobile`, `desktop`, `webcam` | Completed by desktop/webcam scope decision; deferred. |
| 81 | Add DSQV German players | `hydracam`, `mobile`, `users` | Merge with user/player assignment. |
| 82 | Autograbado mode | `hydracam`, `mobile`, `unattended` | Merge with autograbado issue. |
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

Backend-only tests from T-002 through T-015 and T-023 should be moved to the
backend/web tracker unless a mobile mock/integration harness is explicitly in
scope.
