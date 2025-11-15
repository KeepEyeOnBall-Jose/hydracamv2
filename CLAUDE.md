# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HydraCam is a Flutter mobile application for multi-device camera synchronization, designed for sports events (squash, padel). It uses a master-slave architecture where one device (master) controls multiple slave devices' cameras via WebSocket communication over a local network/hotspot.

**Current Platform Status:**
- iOS simulator: Working
- iOS physical device: Installs but shows white screen (active debugging issue)
- Android: In development
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

## Debugging iOS White Screen Issue

Current investigation (from `Current_dev_status.txt`):
- App installs and launches on physical iOS device
- Shows only white screen (no errors in logs)
- Works fine on iOS simulator
- Recent changes: XCode suggested changes accepted, signature added

**Debugging Steps:**
1. Check iOS console logs: `flutter logs` while device connected
2. Verify Info.plist camera/microphone usage descriptions
3. Check main.dart initialization sequence (permissions, camera service)
4. Verify all Flutter plugins have iOS platform implementation
5. Test with minimal main.dart (remove services one by one)

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

- `camera`: 0.10.5+5 - Camera functionality
- `web_socket_channel`: 2.4.0 - WebSocket communication
- `flutter_appauth`: 6.0.7 - Auth0 OAuth2
- `gallery_saver`: 2.3.2 - Save media to device gallery
- `path_provider`: 2.1.1 - Access app documents directory
- `wakelock_plus`: 1.1.4 - Prevent screen sleep during recording
- `provider`: 6.1.2 - State management
- `shared_preferences`: 2.2.2 - Persistent settings storage

## Future Development Priorities

From `GOALS.txt` and README:
1. Fix iOS physical device white screen issue
2. Enable Android and iOS distribution
3. Add Windows/macOS/web platform support
4. Create platform compatibility matrix
5. Abstract sessions into matches/sports/venues
6. Implement AI content processing for highlights
7. Add support for targeting specific slaves (not just broadcast)
8. Expand test coverage