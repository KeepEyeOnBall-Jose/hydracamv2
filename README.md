# HydraCam

## Overview
HydraCam is a mobile application designed for multi-device camera synchronization, intended for sports events like squash or padel matches. It allows a master device to control multiple slave devices' cameras connected via a hotspot. The master device can send commands to start or stop camera recording or capture photos on the slave devices, making it useful for capturing different angles during a sports match.

## Architecture and Components

### Architecture
The application follows a client-server model where:
- The **master device** acts as a server and hotspot, sending commands to connected slave devices.
- **Slave devices** act as WebSocket clients connected to the master, receiving commands and controlling their cameras based on these instructions.

Communication between devices is handled in real-time using WebSockets, enabling the master device to broadcast camera commands simultaneously to all connected slave devices.

### Main Components

#### 1. Services

- **MasterServer**: A WebSocket server running on the master device to manage client connections and send camera control commands.
- **SlaveClient**: A WebSocket client on each slave device to receive commands from the master and trigger camera actions accordingly.
- **CameraService**: Manages camera functionalities on the slave device, such as starting/stopping video recording and taking photos. Includes a callback mechanism to notify when a photo is taken.
- **MasterDiscovery**: A service used by slave devices to discover the master device by listening for broadcast messages.
- **MasterAnnouncer**: Broadcasts the master device's presence periodically to facilitate easy connection from slave devices.
- **PermissionService**: Manages camera and internet permissions on both the master and slave devices, ensuring all required permissions are obtained at runtime.

#### 2. Models

- **CapturedPhoto**: Represents a photo taken by a slave device, containing both the binary data and file path of the photo, the slave device ID, and timestamps for capture and reception.
- **CaptureSession**: Manages the session information, including a list of `CapturedPhoto` objects, session start time, and end time.

#### 3. Screens

- **RoleSelectionScreen** (`screens/role_selection_screen.dart`): The initial screen where the user selects the device role, either "Master" or "Slave."
- **MasterScreen** (`master/master_screen.dart`): The control interface on the master device where the user can send camera commands to the slaves and view received photos.
- **SlaveScreen** (`slave/slave_screen.dart`): The main screen on the slave devices that listens for incoming commands, shows camera status, and displays taken photos in a pop-up dialog.

## Project Structure

lib/
├── main.dart                       # Main entry point of the application.
├── master/
│   ├── master_screen.dart          # Master device's control screen.
│   ├── master_server.dart          # WebSocket server for the master device.
│   └── master_announcer.dart       # Service to broadcast master presence.
├── slave/
│   ├── slave_screen.dart           # Slave device's screen to respond to master commands.
│   ├── slave_client.dart           # WebSocket client for slave devices.
│   └── master_discovery.dart       # Service for discovering the master device.
├── services/
│   ├── camera_service.dart         # Service to manage camera functionalities.
│   └──permission_service.dart     # Service to handle permissions.
├── models/
│   ├── CapturedPhoto.dart          # Model representing a photo captured by a slave device.
│   └── CaptureSession.dart         # Model managing a capture session.
└── widgets/
    └── control_buttons.dart        # Reusable widget with control buttons.

## Photo Management and Memory Optimization
Captured photos are managed efficiently to balance memory usage and persistent storage:
- **On the Slave Device**: Photos are saved to the device's local storage when captured. The binary data is read and sent to the master device, and then the binary data is cleared from memory, retaining only the storage path.
- **On the Master Device**: The received photo binary data is saved to the device's local storage under a session-specific directory. The binary data is then cleared from memory to prevent excessive RAM usage. Photos are accessible via their file paths for display or further processing.
- **Sessions**: Photos are associated with a `CaptureSession`, which keeps the session organized and ready for potential uploading or review. Once a session ends, it is stored in a session history for future reference.

## Next Steps
1. **Video Recording**: Implement video recording functionality for capturing full sports matches.
2. **AI Content Processing**: Develop AI algorithms to process captured content for highlights, player tracking, or other analytical purposes.
3. **Cloud Upload**: Create a service to upload captured videos and photos to a cloud endpoint, along with metadata such as device information and timestamps.
4. **Capture Session(Match) and Clips Abstraction**: Introduce a structure to represent matches and clips, allowing users to start matches and view or manage captured clips.
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
1. Master Device Control:
   - Open MasterScreen to access the control buttons.
   - Tap “Start Camera” to send a command to all connected slave devices to activate their cameras.
   - Tap “Stop Camera” to send a command to all connected slave devices to stop their cameras.

   2. Slave Device Response:
   - Each slave device will respond to the master’s commands and start or stop its camera as instructed.
   - The current state of the camera is displayed on the SlaveScreen.

## Future Enhancements
1. Background Upload Service: Upload captured videos and photos to a cloud endpoint.
2. Detailed Camera Status Feedback: Enable each slave device to provide real-time status back to the master.
3. Multi-angle Capture Synchronization: Enhance timing and synchronization precision for capturing multi-angle views of sports events.




