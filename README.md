# HydraCam

## Overview
HydraCam is a mobile application designed for multi-device camera synchronization, intended for sports events like squash or padel matches. It allows a master device to control multiple slave devices' cameras connected via a hotspot. The master device can send commands to start or stop camera recording or capture photos on the slave devices, making it useful for capturing different angles during a sports match.

## Architecture and Components

### Architecture
The application follows a client-server model where:
- The **master device** acts as a server and hotspot, sending commands to connected slave devices.
- **Slave devices** act as WebSocket clients connected to the master, receiving commands and controlling their cameras based on these instructions.

Communication is managed in real-time using WebSockets, ensuring synchronized camera commands across all connected devices.

### Main Components

#### 1. Master
- **MasterServer**: A WebSocket server running on the master device to manage connections and issue camera commands.
- **MasterAnnouncer**: Broadcasts the master device's presence to help slaves connect.
- **MasterScreen**: The control interface for the master device, showing connected clients and managing media capture and upload.

#### 2. Slave
- **SlaveClient**: A WebSocket client to receive commands from the master and control the camera accordingly.
- **MasterDiscovery**: Service to discover the master device and establish a connection.
- **SlaveScreen**: UI on slave devices to display camera status and handle incoming commands.

#### 3. Models
- **CapturedPhoto**: Stores data about a photo taken, including timestamps and file paths.
- **CapturedVideo**: Stores data about a video recorded, with start and end timestamps and file paths.
- **CaptureSession**: Manages a session's photos and videos, with methods to start and end sessions.

#### 4. Services
- **CameraService**: Handles camera functionality, such as starting and stopping video recording and taking photos.
- **HydraCamApiService**: Manages API communication to upload media files and create capture sessions on the external MoBo API.
- **PermissionService**: Ensures that camera and network permissions are obtained on both master and slave devices.

#### 5. API Communication
- **API Endpoint**: The application communicates with an API hosted on MoBo (keobmotherboardweb) to manage capture sessions.
- **Session Creation**: When a new session starts, the master device sends a request to create a session on the API, receiving a GUID that identifies this session.
- **Media Upload**: The master device uses the session GUID to upload media files (photos and videos) to the API.
- **API Notification**: Although this is still WIP in API, Slave devices use `HydraCamApiService` to notify the external API when they are ready to transmit media. This notification includes the `deviceId` and the `sessionGuid`, ensuring proper association of media files with the active session.

#### 6. Screens
- **RoleSelectionScreen** (`screens/role_selection_screen.dart`): The initial screen where the user selects the device role, either "Master" or "Slave."
- **MasterScreen** (`master/master_screen.dart`): The control interface on the master device where the user can send camera commands to the slaves and view received photos.
- **SlaveScreen** (`slave/slave_screen.dart`): The main screen on the slave devices that listens for incoming commands, shows camera status, and displays taken photos in a pop-up dialog.

## Photo and Video Management
- *On Slave Devices*: Photos and videos are captured and temporarily stored in local storage. The binary data is sent to the master, and then cleared from memory to save resources.
- *On Master Devices*: The master device organizes received media into sessions and saves them locally. Once the session ends, the media is uploaded to the MoBo API.
- **Media Storage**: Both photos and videos captured by slave devices are saved in the device gallery under a specific album named `HydraCam`. This ensures easy access to locally captured media for further use or review.

### Flash Mode Control
When capturing photos or videos, the `enableFlash` parameter can be used to dynamically toggle the flash. For example:
- **Enable Flash**: Use `enableFlash: true` to turn on the flash for the duration of the photo or video capture.
- **Disable Flash**: The flash is automatically turned off after the operation to save battery and avoid unintended usage.
  This behavior is configurable in `CameraService` for both `takePhoto` and `startRecordingVideo`.


## Application Flow
1. The **master device** starts by setting up a WebSocket server and broadcasts its presence.
2. **Slave Device Connection and Synchronization**:
   - Slave devices discover the master using the broadcast and establish a WebSocket connection.
   - After connecting to the master device, each slave sends its `deviceId` and requests the current session status by sending the command `getSessionStatus`.
   - The master responds with session details, allowing slaves to synchronize their actions with the active session.

3. Once connected, the master device sends commands for camera actions (e.g., taking a photo or recording a video) during a capture session.
4. **Captured Media Management**:
   - Captured media is stored locally on each device (slave or master), into a session, and automatically uploaded.
   - Photos and videos are saved in session-specific directories.
   - Additionally, photos are saved in the `HydraCam` album for easy local access.
   - The media can also be manually uploaded from the uploader menu.
5. At the end of the session, the master notifies server and slaves that session has ended.


## Project Structure

lib/
├── master/
│   ├── master_announcer.dart       # Broadcasts the master device's presence.
│   └── master_server.dart          # WebSocket server to communicate with slaves.
├── models/
│   ├── CapturedPhoto.dart          # Represents a captured photo.
│   ├── CapturedVideo.dart          # Represents a recorded video.
│   └── CaptureSession.dart         # Manages a capture session's media and metadata.
├── screens/
│   ├── log_screen.dart             # Displays logs for debugging purposes.
│   ├── master_screen.dart          # Master control interface.
│   ├── role_selection_screen.dart  # Initial screen for selecting device role.
│   ├── settings_screen.dart        # Screen accessible from appbar to access app preferences.
│   ├── slave_screen.dart           # Slave interface for receiving commands.
│   └── uploader_info_screen.dart   # Shows upload status for photos and videos.
├── services/
│   ├── alert_utils.dart            # Utility for showing alerts and pop-ups.
│   ├── auth0_service.dart          # Handles authentication with Auth0 using OAuth2.
│   ├── battery_service.dart        # Monitors device battery level and shows alerts for low battery.
│   ├── camera_service.dart         # Manages camera operations on the devices.
│   ├── device_id_provider.dart     # Provides device identification.
│   ├── device_service.dart         # Retrieves or generates unique device IDs.
│   ├── hydracam_api_service.dart   # Handles API requests to upload media.
│   ├── location_service.dart       # Handles location tracking with geolocator.
│   ├── log_service.dart            # Centralized service for logging events.
│   ├── permission_service.dart     # Ensures necessary permissions are granted.
│   ├── scheduled_task_service.dart # Manages scheduled tasks, such as delayed executions.
│   ├── session_manager.dart        # Handles session logic, shared by master and slaves.
│   ├── settings_service.dart       # Manages read/write configurations over the app.
│   ├── storage_service.dart        # Monitors device free storage and shows alerts for low space.
│   └── uploader_service.dart       # Manages upload queue and retries for media files.
├── slave/
│   ├── master_discovery.dart       # Finds and connects to the master device.
│   └── slave_client.dart           # WebSocket client for slave devices.
├── widgets/
│   ├── camera_preview_widget.dart  # Displays the camera's live preview (slave only).
│   ├── Court_Selection_Widget.dart # Widget for court selection.
│   ├── hydra_cam_app_bar.dart      # Custom app bar with menu options.
│   ├── master_video_recording_screen.dart
│   │                               # Displays camera preview for the master during video recording.
│   └── media_list_widget.dart      # Displays a list of media captured in the current session.
│
├── app_theme.dart                  # Centralized theme system for colors, fonts, and styles.
├── constants.dart                  # Application-wide constants.
├── globals.dart                    # Global variables accessible across the app.
└── main.dart                       # Main entry point of the application.


## Media Management and Memory Optimization
HydraCam handles photos and videos efficiently by leveraging the **SessionManager** and **UploaderService**. Each device (master or slave) independently manages its captured media and uploads directly to the server without transferring large files between devices. This approach minimizes network usage and ensures smooth operation during capture sessions:

- **On All Devices**:
   - Both master and slave devices capture and save media locally using the **CameraService**.
   - Each media item (photo or video) is added to the current session via the **SessionManager**, associating it with metadata such as timestamps, device IDs, and session GUIDs.
   - Captured media is visible only on the device where it was taken, reducing unnecessary network traffic.

- **Session Management**:
   - Media is organized under a `CaptureSession` managed by the **SessionManager**. This ensures all captured items are properly grouped and tracked within the session.
   - Sessions can be ended manually or automatically, with metadata retained for upload and review.

- **UploaderService**:
   - Each device independently queues its media for upload to the server using the **UploaderService**. This avoids delays caused by transferring files between devices.
   - The **UploaderService** handles retries and provides real-time upload status updates to the UI.
   - Media uploads include metadata for proper association on the server, such as the session GUID, device ID, and capture timestamps.



## Additional Explanations

### SessionManager

`SessionManager` is a singleton service that centralizes session management logic for both master and slave devices. It tracks the current session's metadata and provides an API for adding media to the session. Its primary responsibilities include:

- Managing the session GUID and metadata.
- Adding photos and videos to the current session.
- Automatically queuing media for upload via `UploaderService`.
- Notifying listeners (e.g., UI components) whenever the session state changes.

**Usage Example:** Both master and slave devices use `SessionManager` to handle media addition, ensuring consistency across device roles.

---

### UploaderService

`UploaderService` is a singleton responsible for handling the upload of captured media to the API. It uses a queue-based system to ensure reliable uploads, with support for retries and UI notifications. Its key features are:

- Adding media to an upload queue.
- Automatically processing the queue in the background.
- Notifying the UI of upload progress or failures.
- Storing metadata like upload duration and success status.

> **Important:** This service works in tandem with `SessionManager`, fetching the session GUID and media metadata to facilitate accurate uploads.


## Next Steps
1. **Enhanced Session Management**: Abstract sessions into matches, sports, or specific venues (like a court or field).
2. **User Interaction**: Improve the user interface for better control and experience.
3. **AI Content Processing**: Develop AI algorithms to process captured content for highlights, player tracking, or other analytical purposes.
4. **Match, Pitch and and Clips Abstraction**: Introduce a structure to represent matches and clips, allowing users to start matches and view or manage captured clips.
5. **Specific Slave**: Optionally include id of specific slave in websocket messages to give an order to ONE slave instead of all.
6. **Testing**: Populate the `test` folder with widget tests and integration tests to ensure the application functions correctly and efficiently.
---

## Getting Started

### Prerequisites
1. **Flutter SDK** installed.
2. **Android Studio** for Android development or **Xcode** for iOS (if needed).
3. **Devices**: One master device and multiple slave devices to test the multi-device setup.

### Setup Instructions

...

## Usage
1. Connect to same Network:
   - All devices must be in the same network.
   - This typically means the master (or one slave) is acting as a hotspot and the others are connected to its WiFi.
2. Master Device Control:
   - Open MasterScreen to access the control buttons.
   - Tap “Create Session”
   - Tap “Take Picture” or “Start/Stop Video” to send a command to all connected slave devices to stop their cameras.

3. Slave Device Response:
   - Each slave device will respond to the master’s commands and start or stop its camera as instructed.
   - The recorded materials are available in the lower part of the screen for each device along with the uploading state.

## Future Enhancements
...

## Available settings
These are the preferences that one can adjust in the settings screen:
1. Master should record: Controls whether the master should also take a picture or video too when telling slaves to do so.

## App Theme and Visual Style

HydraCam uses a centralized theme system defined in the file `app_theme.dart`. This file contains all the primary colors, typography, and widget styles used throughout the app. It also includes examples of how to apply specific styles to individual widgets.

The theme is applied globally in `main.dart`, ensuring consistent visual styles across the entire app.

### **Modifying Styles**
To customize the app's appearance, you can update the properties in `app_theme.dart`. Changes to colors, fonts, or widget styles will automatically reflect throughout the app. For details, refer to the examples provided within `app_theme.dart`.



