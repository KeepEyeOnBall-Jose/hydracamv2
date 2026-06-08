# AGENTS.md

This file is the canonical agent control plane for this repository. Codex, Claude,
Copilot, and any other coding agent should treat this as the source of truth for
durable project context and working agreements.

## Agent Control Plane

- Keep durable repository guidance in this file. Move transient debugging notes,
  personal scratch plans, and one-off run logs into issue comments, runbooks, or
  `logs/` instead of adding them here.
- `AGENTS.md` remains the canonical agent control plane. Product status,
  roadmap, requirements, imported backlog, architecture, and test strategy live
  under `docs/control/`, with `docs/control/README.md` as the entrypoint.
- The Google Sheet `HydraCam Dev Process` is historical source provenance only;
  do not use it as the canonical control tool. If a sheet row becomes actionable,
  stage it in `docs/control/backlog-import.md` or create a Linear issue once the
  Linear workspace is connected.
- Update this file first when changing shared agent behavior. `CLAUDE.md` and
  `.github/copilot-instructions.md` are compatibility adapters that point back to
  this file to prevent instruction drift.
- Use nested `AGENTS.md` files only when a subtree needs extra scoped guidance.
  Use `AGENTS.override.md` only when a subtree must replace broader guidance.
- Keep instructions concrete and executable: name files, commands, services, and
  expected checks. Avoid generic advice that cannot be verified.
- Before relying on platform status or active-debugging notes, verify them with
  the current code and device state; mobile build state changes frequently.

## Operating Rules

- Run `git status -sb` before editing and before committing. Treat existing
  uncommitted changes as user-owned unless the user explicitly asks to include
  them.
- Stage only files that belong to the current task. Use partial staging when a
  file contains unrelated user changes.
- Prefer small, focused changes over broad rewrites. Match existing Flutter,
  Dart, and script patterns unless there is a clear reason to change them.
- Use `rg` or `rg --files` for repository searches.
- Prefer `LogService.instance.registerLog()` for app logging; do not introduce
  ad hoc `print()` logging in production Flutter code.

## Worktrees and Branch Hygiene

- This checkout is expected to be the main working tree unless Codex or the user
  explicitly places the session in an isolated worktree.
- If a manual project-local worktree is needed, create it under
  `.worktrees/<branch-name>` and keep `.worktrees/` ignored by Git.
- Do not commit nested worktree contents. `worktrees/` is also ignored for legacy
  local layouts.
- Do not remove or prune worktrees outside `.worktrees/`, `worktrees/`, or a
  user-approved location. Check `git worktree list` before cleanup.

## Validation Policy

- For Dart or Flutter code changes, run `flutter analyze` and the most relevant
  `flutter test` target. Use the full `flutter test` suite for shared services,
  session state, WebSocket behavior, or app startup changes.
- For every recurring project-advancement iteration, follow
  `docs/control/evidence-first-loop.md`. Device-facing, UI, release, session,
  network, capture, battery, storage, and upload work requires a run-specific
  evidence pack under `logs/verification-runs/` with screenshots/video/logs from
  real or emulated hardware. Analyzer and unit tests are supporting evidence
  only, except for pure service/model logic.
- For docs-only or instruction-only changes, run `git diff --check` as the
  minimum validation.
- If a check cannot run because a device, SDK, signing identity, backend, or
  credential is unavailable, report the blocker and the command that was skipped.

## Shell and Automation Safety

- Avoid complex one-line shell commands with multiple pipes, nested quoting,
  subshells, or inline Python. Put durable automation in `scripts/`.
- Do not redirect command output to `/dev/null`. Let output display normally or
  save it under `logs/` when a file is needed.
- Add timeouts to network requests in scripts and manual checks so diagnostics do
  not hang indefinitely.

## Project Overview

HydraCam is a Flutter mobile application for multi-device camera synchronization, designed for sports events (squash, padel). It uses a master-slave architecture where one device (master) controls multiple slave devices' cameras via WebSocket communication over a local network/hotspot.

**Current Platform Status:**
- iOS simulator: Working
- iOS physical devices: Working in recent debug/capture evidence. A 2026-06-06
  iPhone 12 Pro debug run launched, created a session, captured/uploaded a
  photo, and started video recording; a 2026-06-06 physical iPad run captured
  one photo and one video after the no-flash camera fix. A 2026-06-07 iPhone
  12 Pro / iOS 26.5 automation rerun passed `ultraWide` capture at
  `sport1080p60` and `detail4k30`; saved-video metadata still reported
  unavailable. A later 2026-06-07 iPhone Profile automation build installed and
  launched without Flutter tooling, exposing an identity-matched bridge at
  `192.168.178.168:4762` for hot role-switch runs. The latest 2026-06-08 iPad
  Profile warm-prime attempt
  `20260608-ipad-warm-prime-after-default-staged-with-host` packaged the
  Profile `Runner.app` into an IPA, installed it with
  `flutter install --use-application-binary`, retried launch twice, then
  xctrace classified the remaining blocker as `ios_profile_not_trusted`; trust
  the developer profile on the iPad before expecting it to join no-tooling hot
  role-switch runs. The
  prior broad "white screen" blocker is superseded; keep validating the
  foreground release/user lane, signing, two-device capture flows, and native
  metadata before production claims.
- Android: In development. Active Android support starts at API 24; Android
  6.0/API 23 and older devices are deprecated for this repo unless the user
  explicitly reopens legacy-device support. 2026-06-07 post-label evidence
  shows Samsung S10e / Android 12 and SM-G960F / Android 10 baseline 1080p30
  capture passing. A later 2026-06-07 parallel independent-capture matrix
  confirmed S10e and G960F under a shared command barrier, while Samsung S7 edge
  still fails before photo save and is classified as
  `s7_exynos_camera_timeout`.
- Multi-device synchronization evidence: the 2026-06-07 parallel matrix was an
  independent local-capture matrix and intentionally launched every
  capture-capable device as a local master. It is not a master/slave discovery
  or broadcast-synchronization proof. Later 2026-06-07 runtime role-switch
  evidence proves one-master/many-slaves role rotation without relaunching on
  the visible physical set, and warm-only mode passes repeated master rotations
  across Samsung G960F, Samsung S7 edge, Samsung S10e, iPhone 12 Pro, and macOS.
  The four-local 2026-06-07 stress proof
  `20260607-runtime-role-switch-slave-ack-poll25ms-staged-skew10-stress5-four-local`
  passes five hot cycles / 20 master rotations in `8.118s` after bridges are
  warm when using `--stage-slaves-after-master-ready`, synchronous
  acknowledgement for the promoted master, async accepted acknowledgement for
  the parallel slave batch, and 25 ms connected-client polling. The current
  iPhone-inclusive repeat proof
  `20260608-warm-summary-prime-five-repeat` uses `--warm-summary` to skip
  Flutter/ADB discovery and master-host probing, launches only the cold iPhone
  Profile bridge, and passes five hot cycles / 25 master rotations in `9.167s`
  across Samsung G960F, Samsung S7 edge, Samsung S10e, iPhone 12 Pro, and macOS.
  Parallel request-start skew was capped below `0.686 ms`, `set_role` averaged
  `162.803 ms`, connected-client verification averaged `201.572 ms`, and every
  selected device became master five times. A separate pure-immediate
  warm-summary rerun `20260608-warm-summary-hot-five-repeat` passes the same
  25 rotations in `8.806s` when every selected bridge is already warm, with no
  discovery, build, install, or launch. The current fastest repeat proof is
  `20260608-latest-cache-shortest-default-staged-five-hot`, which uses the
  automatically persisted latest warm-summary cache with no manual
  `--warm-summary`, no target list, no explicit staged-slave flag, no
  Flutter/ADB discovery, no master-host probing, no build/install/launch, and
  passes the full cached five-device set across five cycles / 25 rotations in
  `7.844s`; warm preflight found no missing bridges and parallel slave
  request-start skew stayed below `1.349 ms`. A fully parallel diagnostic probe
  `20260608-latest-cache-short-command-five-hot-fully-parallel-probe` also
  passed, but took `22.344s` because clients raced the promoted master's server
  startup. The same current code path also has a cold proof, but
  build/install/launch made two cycles / 8 rotations take `63.919s`; do not use
  cold proof as a speed benchmark. Successful warm role-switch runs now update
  `logs/verification-runs/latest-rotating-master-slave-warm-summary.json`.
  Only parsed CLI args with a configured latest-cache path should update that
  durable cache; manually constructed test namespaces must skip cache writes so
  unit tests cannot poison the hot-run target set.
  For the fastest normal repeat loop, run
  `scripts/run_rotating_master_slave_matrix.py` with `--immediate-role-switch`;
  if the latest cache exists, the
  immediate shortcut uses the full cached target set automatically and skips
  Flutter/ADB discovery plus master-host probing. It stages the promoted master
  first, then dispatches all slave role changes in parallel because current
  evidence shows that is faster end-to-end than sending all devices at once.
  Use `--fully-parallel-role-switch` only as a diagnostic comparison. Use
  selected `--target-id` filters only when intentionally narrowing the run.
  Cached immediate reruns
  also skip the default physical-iOS LAN host scan unless
  `--auto-ios-bridge-hosts` is passed explicitly; stale cached iOS hosts are
  caught by the identity-matched warm-bridge preflight. To pin a specific prior
  run instead, pass `--warm-summary
  logs/verification-runs/<last-good-run>/summary.json`. Add repeated
  `--expect-target-id` flags for every device intended to be in the run before
  claiming an all-device or complete selected-set result. That writes
  `expected-targets.json` and fails before build/install/launch when a warm
  summary or filter omits an expected device. This mode must also fail before
  build/install/standby-launch if any selected automation bridge is missing or
  stale. Physical iPhone no-tooling fast launch requires a Profile automation
  build; debug `Runner.app` launched with `devicectl` exits before Dart with
  "Cannot create a FlutterEngine instance in debug mode without Flutter tooling
  or Xcode." Use the runner's `--ios-profile-build-install` path; on older
  physical iOS devices where `devicectl install` cannot see the device, the
  runner falls back to IPA packaging plus `flutter install --use-application-binary`.
  If xctrace reports `ios_profile_not_trusted`, the remaining step is on the
  device: Settings > General > VPN & Device Management, trust the developer
  profile, keep the device unlocked, and rerun the warm-prime/immediate command.
  To avoid restarting the command while doing that device-side step, add
  `--ios-profile-trust-retry-timeout <seconds>` to a warm-prime or
  prime-then-immediate run; the runner will retry the missing physical iOS
  bridge and record `iosProfileTrustRetryAttempts` in `warm-bridge-prime.json`.
  Keep the identity-based auto host scan enabled for immediate loops, and do not
  hard-code the prior stale `192.168.178.141` host. If the iPhone Profile
  bridge may be cold, use `--prime-then-immediate-role-switch --fast-ios-launch`
  as the one-command path; pure `--immediate-role-switch` is intentionally a
  no-launch fast path and should be used only after `/healthz` proves the iPhone
  bridge is currently warm.
  Use `--warm-prime-only` first when selected bridges are cold; it reuses
  running bridges, skips build/install, attempts only missing standby launches,
  writes `warm-bridge-prime.json`, and does not run rotations. Current combined
  runs should prefer `--prime-then-immediate-role-switch`, which primes missing
  bridges and then runs the immediate role-switch proof only when every selected
  bridge is warm. Failed warm-prime artifacts should include `deviceActions`
  with the concrete operator step for each still-missing bridge. Current
  role-switch artifacts should include `requestStartSkewMs` in each
  `runtime-role-switch.json`, per-rotation `phase-timings.json`, and connected
  client `registeredAt` / `masterServerStartedAt` timestamps so parallel
  dispatch, master-command readiness, and connected-client verification are
  measured directly, not inferred from elapsed time. Current timing evidence
  shows dispatch is already sub-millisecond; remaining latency is promoted
  master server startup and client registration after server start. In current
  evidence, staging the master before the slave batch reduces that tail enough
  to beat fully parallel role switching. For macOS standby, prefer the direct
  detached debug-app launcher, but remember that `HYDRACAM_AUTOMATION_PORT` is
  a compile-time Dart define; the direct debug app normally listens on the
  compiled default port `4762`, and the runner normalizes cold direct-macOS
  targets to that port unless an already-running identity-matched bridge is
  adopted. Flutter-launched macOS standby processes have not been reliable warm
  bridges across runner exits. Runtime role switching should keep zero-duration
  automation routes and identity-safe client/socket cleanup; otherwise rapid
  back-to-back rotations can leave stale slave screens or stale sockets that
  dispose or hide the newly promoted master. Use
  `docs/control/status-and-roadmap.md` for the current evidence paths and keep
  capture-enabled master/slave proof separate from role-only proof.
- Desktop (Windows/macOS) and web: Planned for future support

## Development Commands

### Build and Run
```bash
# Get dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Build for specific platforms
flutter build apk              # Android APK
flutter build ios              # iOS (requires Xcode)
flutter build macos            # macOS
flutter build windows          # Windows
```

### Testing and Quality
```bash
# Run tests
flutter test

# Run specific test file
flutter test test/platform_setup_test.dart

# Analyze code for issues
flutter analyze

# Format code (uses double quotes per project style)
flutter format .
```

### Utilities
```bash
# Clean build artifacts
flutter clean

# Generate launcher icons
flutter pub run flutter_launcher_icons:main
```

## Architecture

### Master-Slave Communication Model

**Master Device:**
- Runs WebSocket server on port 4040 (0.0.0.0)
- Broadcasts presence via `MasterAnnouncer`
- Sends commands to all connected slaves (or specific slaves)
- Manages the session GUID and coordinates uploads
- Tracks client connections via heartbeat mechanism

**Slave Device:**
- Discovers master via `MasterDiscovery`
- Connects to master's WebSocket server
- Sends periodic heartbeats to maintain connection
- Executes camera commands (photo, video start/stop)
- Auto-reconnects on disconnection

**Communication Protocol:**
- All communication uses JSON over WebSocket
- Messages include `type`, `command`, and `deviceId` fields
- Supports scheduled commands with countdown timers
- Heartbeat interval: 10 seconds (inactivity threshold in `constants.dart`)

### Singleton Services

The app uses several singleton services for centralized state management:

**CameraServiceSingleton** (`lib/services/camera_service_singleton.dart`):
- Provides single shared camera instance across master/slave roles
- Prevents redundant camera initializations
- Supports dynamic callback assignment for role switching
- Handles forced recording stops (low storage/battery)

**SessionManager** (`lib/services/session_manager.dart`):
- Manages current session state (GUID, metadata)
- Tracks captured photos and videos in `CaptureSession` objects
- Automatically queues media for upload via `UploaderService`
- Persists session metadata to `{app_documents}/session_{guid}/metadata.json`
- Supports session reconstruction from filesystem

**UploaderService** (`lib/services/uploader_service.dart`):
- Queue-based upload system with retry logic
- Configurable auto-upload via settings
- Uploads directly from each device (no master-slave transfer)
- Notifies UI of upload progress via `ValueNotifier`
- Respects "delete local files after upload" setting

### Key Data Models

**CaptureSession** (`lib/models/CaptureSession.dart`):
- Groups photos and videos for a recording session
- Tracks session GUID, start/end times, device type
- Maintains lists of `CapturedPhoto` and `CapturedVideo` objects

**CapturedPhoto** (`lib/models/CapturedPhoto.dart`):
- Stores photo path, device ID, capture/received timestamps
- Tracks upload status and duration

**CapturedVideo** (`lib/models/CapturedVideo.dart`):
- Stores video path, device ID, start/end recording timestamps
- Tracks upload status and duration

### Authentication and API

**Auth0 Integration:**
- OAuth2 authentication via `flutter_appauth` package
- Handled by `Auth0Service` (`lib/services/auth0_service.dart`)
- M2M (machine-to-machine) support in `Auth0M2MService`

**API Communication:**
- `HydraCamApiService` manages all backend API calls
- Creates sessions, uploads media (photos/videos)
- Associates uploads with session GUID and device ID
- Backend: MoBo (keobmotherboardweb) API

### Resource Management

**BatteryService** (`lib/services/battery_service.dart`):
- Monitors battery level continuously
- Shows alerts for low battery
- Can trigger forced recording stop

**StorageService** (`lib/services/storage_service.dart`):
- Monitors available disk space
- Configured thresholds: 1.5GB (low), 0.5GB (critical)
- Forces recording stop on critical storage
- Shows snackbar notifications

**PermissionService** (`lib/services/permission_service.dart`):
- Requests camera, microphone, storage, location permissions
- Called in `main()` before app initialization

### Application Entry Point

**main.dart:**
- Initializes permissions, device ID, location service
- Enables wakelock (prevents screen timeout)
- Sets up Provider dependencies (DeviceIdProvider, StorageService, BatteryService, CameraService)
- Applies centralized theme from `app_theme.dart`
- Default screen: `SlaveScreen(isAutoMode: true)`

## Code Style and Conventions

### Dart/Flutter Guidelines
- **Imports:** Use relative imports (enforced by `prefer_relative_imports` lint)
- **Strings:** Use double quotes (enforced by `prefer_double_quotes` lint)
- **Variables:** Prefer `final` for local variables (enforced by `prefer_final_locals` lint)
- **Null safety:** Always require non-null named parameters where applicable
- **Logging:** Use `LogService.instance.registerLog()` for all logging

### File Organization
```
lib/
├── master/          # Master device WebSocket server, announcer, UI
├── slave/           # Slave device WebSocket client, discovery, UI
├── models/          # Data models (CaptureSession, CapturedPhoto, CapturedVideo)
├── screens/         # Full-page UI screens (login, settings, sessions, etc.)
├── services/        # Singleton services and utilities
├── widgets/         # Reusable UI components
├── app_theme.dart   # Centralized theme (colors, typography, widget styles)
├── constants.dart   # App-wide constants (courts, timeouts, thresholds)
├── globals.dart     # Global variables
└── main.dart        # Application entry point
```

## Session and Media Workflow

1. **Session Start:**
   - Master creates session → receives GUID from API
   - Calls `SessionManager.instance.startSession(guid, sessionId, deviceType: "Master")`
   - Slaves connect and request session status via `getSessionStatus` command
   - Master responds with `sessionStatus` or `noSession` message

2. **Media Capture:**
   - Master sends command (e.g., `{"command": "takePhoto"}`)
   - Each device captures media using `CameraService`
   - Media added to `SessionManager.currentSession`
   - Automatically queued in `UploaderService`

3. **Media Storage:**
   - Saved to `{app_documents}/session_{guid}/{filename}`
   - Also saved to device gallery under "HydraCam" album
   - Metadata persisted to `metadata.json` in session directory

4. **Upload:**
   - Each device uploads its own media (no master-slave transfer)
   - Includes session GUID, device ID, timestamps in upload
   - Configurable auto-upload in settings
   - Manual upload available from uploader info screen

5. **Session End:**
   - Master calls `SessionManager.instance.endSession()`
   - Updates metadata.json with end time
   - Resets uploader queue
   - Slaves notified via WebSocket

## Settings and Configuration

**Available Settings** (stored via `SettingsService` using `shared_preferences`):
- `masterShouldRecord`: Whether master device also captures when commanding slaves
- `autoUploadMaterials`: Enable automatic upload after capture
- `deleteLocalAfterUpload`: Delete local files after successful upload
- Camera quality presets (high/medium/low) - see `CameraQuality` enum in `constants.dart`

**Hardcoded Configuration** (in `constants.dart`):
- `secondsToClosePhoto = 3`: Auto-close photo preview popup
- `timeToStopSearching = 3`: Slave auto-becomes master if no master found
- `inactivityThreshold = 10`: Disconnect inactive slave clients (seconds)
- `locationTimeout = 5`: Max time for location service to get position
- Court/sports center GUIDs: Hardcoded list in `groupedCourts` map

## iOS Physical-Device Verification

Current status lives in `docs/control/status-and-roadmap.md`. Latest physical
iOS evidence:
- `logs/verification-runs/2026-06-06-iphone-personal-team-debug/` launched
  Debug on iPhone 12 Pro / iOS 26.4.2 through `flutter run`, received camera
  and microphone permissions, reached master mode, created a session, captured
  and uploaded a photo, and started video recording.
- `logs/verification-runs/20260606-2310-ipad-capture-failure-trace-and-repro/`
  fixed the iPad no-flash camera path and passed a physical iPad repro with one
  photo and one video captured.
- User follow-up on 2026-06-07 reports iPad and iPhone 12 testing is working
  OK.

The old "installs but only shows white screen" status is no longer current.
Future iOS debugging should focus on reproducible failing flows only: release
or profile icon launch, signing/team differences, two-device capture, local
network discovery, upload, and session lifecycle.

## Common Patterns

### Adding a New Screen
1. Create file in `lib/screens/`
2. Import `app_theme.dart` for consistent styling
3. Use `HydraCamAppBar` widget for consistent header
4. Register logging for user actions via `LogService`

### Adding a New WebSocket Command
1. Define command in master's send method (`MasterServer`)
2. Add handler in slave's message listener (`SlaveClient`)
3. Include `deviceId` in all messages
4. Support scheduled commands with `scheduledTime` field for countdown

### Working with Sessions
```dart
// Start session
SessionManager.instance.startSession(guid, sessionId, deviceType: "Master");

// Add media
final photo = CapturedPhoto(...);
SessionManager.instance.addPhoto(photo); // Auto-queues for upload

// Check session state
if (SessionManager.instance.isSessionActive) {
  final guid = SessionManager.instance.sessionGuid;
}

// End session
SessionManager.instance.endSession();
```

### Camera Operations
```dart
// Access singleton
final cameraService = CameraServiceSingleton.instance;

// Take photo
await cameraService.takePhoto(enableFlash: true);

// Record video
await cameraService.startRecordingVideo(enableFlash: false);
await cameraService.stopRecordingVideo();
```

## Testing Notes

- Test directory: `test/`
- Widget tests should use `testWidgets()`
- Current test files: `widget_test.dart`, `platform_setup_test.dart`
- Run tests after any service/singleton changes
- Test both master and slave roles independently

## Dependencies of Note

- `camera`: ^0.11.4 - Camera functionality; current iOS evidence also uses
  `camera_avfoundation` 0.9.23+2 from the lockfile.
- `web_socket_channel`: ^3.0.3 - WebSocket communication
- `flutter_appauth`: ^11.0.0 - Auth0 OAuth2
- `photo_manager`: ^3.6.3 - Save/manage media; `gallery_saver` was removed for
  current Android Gradle compatibility.
- `path_provider`: 2.1.1 - Access app documents directory
- `wakelock_plus`: 1.1.4 - Prevent screen sleep during recording
- `provider`: 6.1.2 - State management
- `shared_preferences`: 2.2.2 - Persistent settings storage

## Future Development Priorities

Current goals and roadmap live in `docs/control/status-and-roadmap.md`. Durable
priority themes:
1. Complete release-grade Android and iOS distribution readiness
2. Validate repeated two-device iOS/Android master-slave capture flows
3. Add Windows/macOS/web platform support
4. Create platform compatibility matrix
5. Abstract sessions into matches/sports/venues
6. Implement AI content processing for highlights
7. Add support for targeting specific slaves (not just broadcast)
8. Expand test coverage
