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
- At the end of every substantive turn, explicitly consider "what should our
  next steps be?" and include a clear ordered sequence of 2 to 4 next actions.
  Keep the sequence concrete and grounded in the current evidence, blockers, and
  project priorities. If the work is fully complete, list the most useful
  follow-up checks or decisions rather than padding with generic tasks.

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
- For user-requested app behavior or UI changes, the change must manifest on
  connected devices in the same turn whenever the relevant hardware is attached
  and responsive. After analyzer/unit/widget tests pass, build/install/launch
  the current checkout on the connected target devices and cross-check the
  affected route in the running app. Do not report device-facing UI work as done
  from local tests alone when the user has connected hardware available.
- Use `scripts/run_hardware_ui_e2e.py` as the default same-turn hardware UI
  smoke for Android devices. Select the affected devices with repeated
  `--device <adb-serial>` flags, select routes with repeated `--route setup` or
  `--route standby`, and store results under `logs/verification-runs/<run>/`.
  The script builds the current app with `HYDRACAM_AUTOMATION=true`, installs it
  on selected hardware, launches the requested app routes, captures in-app
  screenshots through `capture_screenshot`, performs a real device swipe plus a
  second screenshot for scroll-checked routes such as `setup`, collects logs,
  and fails on Flutter overflow markers.
- For every recurring project-advancement iteration, follow
  `docs/control/evidence-first-loop.md`. Device-facing, UI, release, session,
  network, capture, battery, storage, and upload work requires a run-specific
  evidence pack under `logs/verification-runs/` with screenshots/video/logs from
  real or emulated hardware. Analyzer and unit tests are supporting evidence
  only, except for pure service/model logic.
- For regular app-change evaluation, use
  `docs/control/regular-evaluation-plan.md` to choose the static, emulator,
  hardware, multi-device, and release gates. Re-inventory devices every run and
  do not treat emulator/simulator output as camera, gallery, local-network, or
  release/profile proof.
- Before hardware role-switch or capture checks in a new or changed venue,
  verify that every selected device is on the same reachable LAN. For attached
  Android devices, run `scripts/android_wifi_preflight.py` with
  `HYDRACAM_WIFI_SSID` and `HYDRACAM_WIFI_PASSWORD` supplied from the local
  shell environment or keychain, use `--expected-subnet auto` or
  `--expected-host <known-bridge-ip>`, and never write Wi-Fi passphrases into
  repository files or evidence logs. iOS devices usually
  cannot be silently provisioned by Codex unless they are supervised or receive
  an approved configuration profile; verify iOS network readiness through the
  automation bridge `/healthz`, visible local IP/subnet, or on-device Wi-Fi
  settings.
- For docs-only or instruction-only changes, run `git diff --check` as the
  minimum validation.
- If a check cannot run because a device, SDK, signing identity, backend, or
  credential is unavailable, report the blocker and the command that was skipped.
- `scripts/agent_gate.sh` mechanically runs the change-scoped static subset of
  this policy on every turn, and `.github/workflows/` CI backstops
  `flutter analyze`/`flutter test` on every PR; see "Mechanical Enforcement"
  below for how these are wired and what to do if they misbehave.
- For the rotating master/slave matrix runner's mode flags, target-selection
  behavior, and iOS/macOS bridge caveats, see
  `docs/control/rotating-matrix-runner.md`.

## Mechanical Enforcement

- `scripts/agent_gate.sh` computes changed files (staged + unstaged +
  untracked vs `HEAD`, or explicit path arguments) and always runs
  `git diff --check`; it also runs `dart format --set-exit-if-changed` plus
  `flutter analyze --no-pub` for changed `.dart` files, and
  `markdownlint-cli2` for changed `.md` files (excluding
  `docs/control/history/` and `logs/`).
- `.claude/settings.json` wires this script into Claude Code's `Stop` hook, so
  it runs automatically at the end of every turn. If the hook proves too
  chatty or slow, the fallback is to remove the `hooks.Stop` entry; the script
  remains runnable manually (`bash scripts/agent_gate.sh`).
- `.github/workflows/docs-quality.yml` backstops `git diff --check` and
  changed-markdown linting on every PR and push to `master-jose-2025`.
  `.github/workflows/flutter-quality.yml` backstops `dart format
  --set-exit-if-changed` (scoped to `lib test tool integration_test`),
  `flutter analyze`, and `flutter test` the same way.
- `.github/workflows/scripts-quality.yml` backstops, on the same PR/push
  triggers: running every `scripts/test_*.py` directly with `python3` (all
  except `scripts/test_endpoints.py`, a live-network probe script excluded by
  name); `shellcheck --severity=error` over `scripts/*.sh` and root `*.sh`
  (`.zsh` scripts are not linted — shellcheck does not support zsh); and a
  large-file guard failing on any added/modified file over 1MB in the diff.
- Once a check is mechanically enforced here (gate script or CI workflow), do
  not re-expand it into prose elsewhere in this file — update the script or
  workflow and this section's pointer instead.

## Shell and Automation Safety

- Avoid complex one-line shell commands with multiple pipes, nested quoting,
  subshells, or inline Python. Put durable automation in `scripts/`.
- Do not redirect command output to `/dev/null`. Let output display normally or
  save it under `logs/` when a file is needed.
- Add timeouts to network requests in scripts and manual checks so diagnostics do
  not hang indefinitely.

## Project Overview

HydraCam is a Flutter mobile application for multi-device camera synchronization, designed for sports events (squash, padel). It uses a master-slave architecture where one device (master) controls multiple slave devices' cameras via WebSocket communication over a local network/hotspot.

**Current Platform Status** (durable summary; see `docs/control/status-and-roadmap.md`
for dated evidence, run IDs, IPs, and timings, and
`docs/control/rotating-matrix-runner.md` for multi-device runner how-to):

- iOS: Simulator launches but exposes no camera (launch/UI checks only).
  Physical iPhone/iPad work for capture, session, upload, and role-switch on
  Profile automation builds; known caveats are debug builds cannot fast-launch
  without Flutter tooling, an untrusted developer profile blocks the
  automation bridge until approved on-device, and TestFlight/App Store upload
  is blocked on local Distribution signing plus App Store Connect credentials.
- Android: Active support starts at API 24 (older devices deprecated unless
  reopened). Role-switch/capture evidence is good on Samsung S10e/G960F. The
  Samsung S7 edge (SM-G935F) needs an implemented device-specific
  compatibility mode (preset-default FPS, capture retry) with current
  1080p30 photo/video proof. The user cleared Xiaomi 2201116PG's account/SIM
  authorization gate on 2026-07-14; current-build `1.4.0+19` now installs,
  updates unattended after MIUI remembers the approval, and launches on the
  physical POCO. Camera/session proof remains pending on the fleet LAN.
- Desktop (Windows/macOS) and web: Partial. macOS controller debug path works.
  A Windows/Linux/Android-emulator proof passed native Windows real-webcam
  capture/upload but did not complete the full role matrix; see
  `docs/control/win11-triple-platform-proof-wrapup-2026-06-09.md`.
- Multi-device role-switch synchronization across mixed iOS/Android/macOS sets
  (including six-device rotations) is implemented and proven; see the two
  pointers above for how to run it and the latest timings.

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
- Initializes the CameraServiceSingleton (with a StorageService) before running the app
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

```text
lib/
├── master/          # Master device WebSocket server, announcer, UI
├── slave/           # Slave device WebSocket client, discovery, UI
├── models/          # Data models (CaptureSession, CapturedPhoto, CapturedVideo)
├── screens/         # Full-page UI screens (login, settings, sessions, etc.)
├── services/        # Singleton services and utilities
├── widgets/         # Reusable UI components
├── app_theme.dart   # Centralized theme (colors, typography, widget styles)
├── constants.dart   # App-wide constants (courts, timeouts, thresholds)
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
