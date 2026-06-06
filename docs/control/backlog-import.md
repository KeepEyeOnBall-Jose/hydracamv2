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

### 1. Fix iOS physical-device launch white screen

- Source: current repo status; related `FALLOS Y MEJORAS` rows 12, 13, 15, 16,
  17.
- Labels: `hydracam`, `mobile`, `ios`, `release-blocker`.
- Priority: High.
- Body: The app installs and launches on physical iOS devices but shows a white
  screen. Related sheet rows also describe iOS networking, disconnect, iPad save,
  and role-selection issues.
- Acceptance checks: physical iPhone reaches the expected first app screen,
  logs show successful initialization or actionable errors, and simulator
  behavior remains unchanged.

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

### 11. Desktop/webcam scope decision completed

- Sources: `JAVI IMMEDIATE BACKLOG` rows 76, 83, 103.
- Labels: `hydracam`, `mobile`, `desktop`, `webcam`.
- Priority: Low.
- Disposition: Completed in `docs/control/status-and-roadmap.md` on 2026-06-06.
- Decision: desktop is monitoring/development-only for now; webcam capture is
  deferred. Do not create a live Linear issue for generic webcam capture unless
  the scope is reopened with a concrete workflow.

### 12. Add mobile preview streams on master

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
| 31 | Fallo | iPad camera does not save photos | `hydracam`, `mobile`, `ios`, `camera` | Merge with iOS reliability. |
| 32 | Mejora | Old media should not require a specific filter | `hydracam`, `mobile`, `gallery` | Merge with gallery session attachment. |
| 33 | Fallo | iPhone/iPad auto-connect from mode selection but do not advance | `hydracam`, `mobile`, `ios`, `navigation` | Merge with iOS reliability. |
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
| T-001 | Auth0 login regression test | `hydracam`, `mobile`, `testing`, `auth` |
| T-016 | Photo/video upload API test with invalid files | `hydracam`, `mobile`, `testing`, `upload`, `external-backend` |

Backend-only tests from T-002 through T-015 and T-023 should be moved to the
backend/web tracker unless a mobile mock/integration harness is explicitly in
scope.
