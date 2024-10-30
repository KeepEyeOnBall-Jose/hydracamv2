# SportCamSync

## Overview
SportCamSync is a mobile application designed for multi-device camera synchronization, intended for sports events like squash or padel matches. It allows a master device to control multiple slave devices’ cameras connected via a hotspot. The master device can start or stop camera recording or capture photos on the slave devices, which is useful for capturing different angles during a sports match.

## Architecture and Components

### Architecture
The application follows a client-server model where:
- The **master device** acts as a server and hotspot, sending commands to connected slave devices.
- **Slave devices** act as WebSocket clients connected to the master, receiving commands and controlling their cameras based on these instructions.

Communication between devices is handled in real-time using WebSockets, making it possible for the master device to broadcast camera commands simultaneously to all connected slave devices.

### Main Components

#### 1. Services

- **MasterServer**: A WebSocket server running on the master device to manage client connections and send camera control commands.
- **SlaveClient**: A WebSocket client on each slave device to receive commands from the master and trigger camera actions accordingly.
- **CameraService**: Handles camera functionalities on the slave device, such as starting/stopping video recording and taking photos.
- **PermissionService**: Manages camera and internet permissions on both the master and slave devices, ensuring all required permissions are obtained at runtime.

#### 2. Screens

- **MasterScreen** (`master/master_screen.dart`): The control interface on the master device where the user can send camera commands to the slaves.
- **SlaveScreen** (`slave/slave_screen.dart`): The main screen on the slave devices that listens for incoming commands and shows camera status.

#### 3. Widgets

- **ControlButtons** (`widgets/control_buttons.dart`): A reusable widget on the master screen, providing buttons to send camera start/stop commands to the slave devices.

## Project Structure
lib/
├── main.dart                       # Main entry point of the application.
├── master/
│   ├── master_screen.dart          # Master device's control screen.
│   ├── master_server.dart          # WebSocket server for the master device.
├── slave/
│   ├── slave_screen.dart           # Slave device's screen to respond to master commands.
│   ├── slave_client.dart           # WebSocket client for slave devices.
├── services/
│   ├── camera_service.dart         # Service to manage camera functionalities.
│   ├── permission_service.dart     # Service to handle permissions.
└── widgets/
    ├── control_buttons.dart        # Reusable widget with control buttons.


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




