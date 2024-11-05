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

#### 6. Screens
- **RoleSelectionScreen** (`screens/role_selection_screen.dart`): The initial screen where the user selects the device role, either "Master" or "Slave."
- **MasterScreen** (`master/master_screen.dart`): The control interface on the master device where the user can send camera commands to the slaves and view received photos.
- **SlaveScreen** (`slave/slave_screen.dart`): The main screen on the slave devices that listens for incoming commands, shows camera status, and displays taken photos in a pop-up dialog.

## Photo and Video Management
- *On Slave Devices*: Photos and videos are captured and temporarily stored in local storage. The binary data is sent to the master, and then cleared from memory to save resources.
- *On Master Devices*: The master device organizes received media into sessions and saves them locally. Once the session ends, the media is uploaded to the MoBo API.

## Application Flow
1. The **master device** starts by setting up a WebSocket server and broadcasts its presence.
2. **Slave devices** discover the master using the broadcast and establish a WebSocket connection.
3. Once connected, the master device sends commands for camera actions (e.g., taking a photo or recording a video) during a capture session.
4. Captured media is transferred from slave devices to the master, organized into a session, and saved to local storage.
5. At the end of the session, the master device uploads the media files to an external API.


## Project Structure

lib/
├── main.dart                       # Main entry point of the application.
├── master/
│   ├── master_screen.dart          # UI for the master device.
│   ├── master_server.dart          # WebSocket server to communicate with slaves.
│   └── master_announcer.dart       # Broadcasts the master device's presence.
├── slave/
│   ├── slave_screen.dart           # UI for slave devices to receive commands.
│   ├── slave_client.dart           # WebSocket client for slave devices.
│   └── master_discovery.dart       # Finds and connects to the master device.
├── services/
│   ├── camera_service.dart         # Manages camera operations on the slave devices.
│   ├── hydracam_api_service.dart   # Handles API requests to upload media.
│   └── permission_service.dart     # Ensures necessary permissions are granted.
├── models/
│   ├── CapturedPhoto.dart          # Represents a captured photo.
│   ├── CapturedVideo.dart          # Represents a recorded video.
│   └── CaptureSession.dart         # Manages a capture session's media and metadata.
├── screens/
│   ├── master_screen.dart          # Master control interface.
│   ├── role_selection_screen.dart  # Initial screen for selecting device role.
│   └── slave_screen.dart           # Slave interface for receiving commands.
└── widgets/
└── control_buttons.dart        # Reusable widget for control buttons.


## Media Management and Memory Optimization
Captured photos and videos are managed efficiently to balance memory usage and persistent storage:
- **On the Slave Device**: Photos are saved to the device's local storage when captured. The binary data is read and sent to the master device, and then the binary data is cleared from memory, retaining only the storage path.
- **On the Master Device**: The received photo binary data is saved to the device's local storage under a session-specific directory. The binary data is then cleared from memory to prevent excessive RAM usage. Photos are accessible via their file paths for display or further processing.
- **Sessions**: Photos are associated with a `CaptureSession`, which keeps the session organized and ready for potential uploading or review. Once a session ends, it is stored in a session history for future reference.

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
0. Connect to same Network:
   - All devices must be in the same network.
   - This typically means the master (or one slave) is acting as a hotspot and the others are connected to its WiFi.
1. Master Device Control:
   - Open MasterScreen to access the control buttons.
   - Tap “Create Session”
   - Tap “Start Camera” to send a command to all connected slave devices to activate their cameras.
   - Tap “Take Picture” “Start/Stop Video” to send a command to all connected slave devices to stop their cameras.

2. Slave Device Response:
   - Each slave device will respond to the master’s commands and start or stop its camera as instructed.
   - The current state of the camera is displayed on the SlaveScreen.

## Future Enhancements
1. Background Upload Service: Upload captured videos and photos to a cloud endpoint.
2. Detailed Camera Status Feedback: Enable each slave device to provide real-time status back to the master.
3. Multi-angle Capture Synchronization: Enhance timing and synchronization precision for capturing multi-angle views of sports events.




