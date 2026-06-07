import "dart:async";
import "dart:convert"; // Import for jsonDecode
import "dart:io";
import "package:flutter/foundation.dart";
import "../globals.dart";
import "../models/capture_session.dart";
import "package:path_provider/path_provider.dart";
// import "package:gallery_saver/gallery_saver.dart";  // Temporarily disabled - incompatible plugin
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/camera_service.dart";
import "../services/gallery_persistence_service.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";
import "../services/session_manager.dart";

/// MasterServer - Handles the master device's WebSocket server.
/// This class manages communication with slave devices, tracks active connections,
/// receives captured media, and manages sessions via the `SessionManager`.
///
/// ### Responsibilities:
/// - Starts and stops a WebSocket server for handling slave connections.
/// - Manages client registrations and disconnections.
/// - Receives media (photos and videos) from slave devices and adds them to the active session.
/// - Sends commands to all connected slaves or specific devices.
/// - Tracks the heartbeat of connected clients to identify inactive ones.

class ConnectedDeviceInfo {
  final String deviceId;
  final String? remoteIp;
  final NetworkSnapshot? networkSnapshot;
  final ConnectedDeviceNetworkStatus networkStatus;
  final DateTime lastSeen;

  const ConnectedDeviceInfo({
    required this.deviceId,
    required this.networkStatus,
    required this.lastSeen,
    this.remoteIp,
    this.networkSnapshot,
  });

  String get shortDeviceId {
    if (deviceId.length <= 8) {
      return deviceId;
    }
    return deviceId.substring(0, 8);
  }

  ConnectedDeviceInfo copyWith({
    String? remoteIp,
    NetworkSnapshot? networkSnapshot,
    ConnectedDeviceNetworkStatus? networkStatus,
    DateTime? lastSeen,
  }) {
    return ConnectedDeviceInfo(
      deviceId: deviceId,
      remoteIp: remoteIp ?? this.remoteIp,
      networkSnapshot: networkSnapshot ?? this.networkSnapshot,
      networkStatus: networkStatus ?? this.networkStatus,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class MasterServer {
  HttpServer? _server;
  final Map<String, WebSocket> _clients =
      {}; // Map to store clients with deviceId as key
  final Map<String, DateTime> _lastHeartbeat =
      {}; // Track last heartbeat per client
  final Map<String, ConnectedDeviceInfo> _clientInfo = {};
  NetworkSnapshot? _masterNetworkSnapshot;
  Timer? _heartbeatCheckTimer; // Timer for checking inactive clients
  // CaptureSession? currentSession; // Current Capture Session is now used in Session Manager Singleton
  List<CaptureSession> sessionHistory =
      []; // List to store past sessions TODO: EXTRACT TO MANAGER TOO
  Function(int)? onClientCountChange;
  Function(dynamic)? onMediaReceived; // Callback for media reception
  Function(String, int)?
      onClientRemoved; // Callback for managing slaves disconnecting

  /// Camera service is used for capturing media directly on the master device
  final CameraService cameraService;

  /// Optional constructor for MasterServer. Probably will be deleted
  ///
  /// - `cameraService`: The service to handle camera-related operations.
  MasterServer(this.cameraService);

  /// Starts the WebSocket server on the master device and initializes the heartbeat check mechanism.
  /// This method binds to a specific port and listens for incoming connections.
  Future<void> startServer() async {
    try {
      _server = await HttpServer.bind("0.0.0.0", 4040);
      LogService.instance
          .registerLog("WebSocket Server successfully started on port 4040");

      // Init check to verify inactive clients
      _startHeartbeatCheck();

      await for (HttpRequest request in _server!) {
        if (request.uri.path == "/ws") {
          final remoteIp = request.connectionInfo?.remoteAddress.address;
          final socket = await WebSocketTransformer.upgrade(request);
          LogService.instance.registerLog("New WebSocket client connected.");

          String? deviceId;

          // Listen to client messages
          socket.listen((data) async {
            try {
              // Decode message
              final decodedData = jsonDecode(data as String);
              LogService.instance
                  .registerLog("Data received from slave: $decodedData");

              if (decodedData is Map<String, dynamic>) {
                final String? messageType = decodedData["type"];
                deviceId = decodedData["deviceId"] ?? "Unknown";

                // Register client
                if (messageType == "deviceId") {
                  if (deviceId != null) {
                    await _registerOrUpdateClient(
                      deviceId: deviceId!,
                      socket: socket,
                      remoteIp: remoteIp,
                      networkSnapshot:
                          NetworkSnapshot.tryFromJson(decodedData["network"]),
                    );
                    LogService.instance.registerLog(
                        "Registered new slave with deviceId: $deviceId");

                    // After registering the slave, send the session status
                    if (SessionManager.instance.isSessionActive &&
                        SessionManager.instance.sessionGuid != null) {
                      // Send session status
                      final sessionStatusMessage = jsonEncode({
                        "command": "sessionStatus",
                        "sessionGuid": SessionManager.instance.sessionGuid,
                      });

                      // Send the message to the client
                      socket.add(sessionStatusMessage);

                      LogService.instance.registerLog(
                          "Sent sessionStatus to $deviceId: $sessionStatusMessage");
                    } else {
                      // No active session
                      final noSessionMessage = jsonEncode({
                        "command": "noSession",
                      });

                      // Send the message to the client
                      socket.add(noSessionMessage);

                      LogService.instance
                          .registerLog("Sent noSession to $deviceId");
                    }
                  }
                }

                // Receive media
                else if (messageType == "photo" || messageType == "video") {
                  // Process media data
                  final Uint8List binaryData =
                      Uint8List.fromList(List<int>.from(decodedData["data"]));
                  final String filePath = await _saveMediaLocally(
                      binaryData, messageType == "photo");
                  final DateTime receivedDate = DateTime.now();

                  if (messageType == "photo") {
                    final DateTime captureDate =
                        DateTime.parse(decodedData["captureDate"]);
                    final receivedPhoto = CapturedPhoto(
                      photoData: null,
                      photoPath: filePath,
                      captureDate: captureDate,
                      receivedDate: receivedDate,
                      slaveDeviceId: deviceId!,
                    );
                    //currentSession?.addPhoto(receivedPhoto);
                    // Add photo via SessionManager
                    SessionManager.instance.addPhoto(receivedPhoto);

                    onMediaReceived?.call(receivedPhoto);
                    LogService.instance.registerLog(
                        "Photo from slave device ($deviceId) received and stored at: $filePath");
                  } else if (messageType == "video") {
                    final DateTime startRecordingDate =
                        DateTime.parse(decodedData["startRecordingDate"]);
                    final DateTime endRecordingDate =
                        DateTime.parse(decodedData["endRecordingDate"]);
                    final receivedVideo = CapturedVideo(
                      videoData: null,
                      videoPath: filePath,
                      slaveDeviceId: deviceId!,
                      startRecordingDate: startRecordingDate,
                      endRecordingDate: endRecordingDate,
                      receivedDate: receivedDate,
                    );
                    //currentSession?.addVideo(receivedVideo);
                    // Add photo via SessionManager
                    SessionManager.instance.addVideo(receivedVideo);
                    onMediaReceived?.call(receivedVideo);
                    LogService.instance.registerLog(
                        "Video from slave device ($deviceId) received and stored at: $filePath");
                  }
                }

                // Receive heartbeats from slaves
                else if (messageType == "heartbeat") {
                  if (deviceId != null) {
                    _lastHeartbeat[deviceId!] =
                        DateTime.now(); // Update last heartbeat
                    await _registerOrUpdateClient(
                      deviceId: deviceId!,
                      socket: socket,
                      remoteIp: remoteIp,
                      networkSnapshot:
                          NetworkSnapshot.tryFromJson(decodedData["network"]),
                    );
                    LogService.instance
                        .registerLog("Received heartbeat from $deviceId");
                  }
                }

                // Respond to explicit requests on session status
                else if (messageType == "getSessionStatus") {
                  // Handle getSessionStatus
                  LogService.instance
                      .registerLog("Received getSessionStatus from $deviceId");

                  // Prepare response
                  if (SessionManager.instance.isSessionActive &&
                      SessionManager.instance.sessionGuid != null) {
                    // Send session status
                    final sessionStatusMessage = jsonEncode({
                      "command": "sessionStatus",
                      "sessionGuid": SessionManager.instance.sessionGuid,
                    });

                    // Send the message to the client
                    socket.add(sessionStatusMessage);

                    LogService.instance.registerLog(
                        "Sent sessionStatus to $deviceId: $sessionStatusMessage");
                  } else {
                    // No active session
                    final noSessionMessage = jsonEncode({
                      "command": "noSession",
                    });

                    // Send the message to the client
                    socket.add(noSessionMessage);

                    LogService.instance
                        .registerLog("Sent noSession to $deviceId");
                  }
                }

                // Process forced stop interruptions from slaves
                else if (messageType == "forcedStop") {
                  final deviceId = decodedData["deviceId"];
                  final reason = decodedData["reason"]; // e.g. "storageFull"
                  LogService.instance.registerLog(
                      "Slave $deviceId forcibly stopped. Reason: $reason");

                  // Show snackbar in screen
                  LogService.instance
                      .registerLog("Slave $deviceId forcibly stopped: $reason");
                }
              } else {
                LogService.instance
                    .registerLog("Unexpected data format received: $data");
              }
            } catch (e) {
              LogService.instance.registerLog("Error decoding data: $e");
            }
          }, onDone: () {
            // Manage client disconnection
            if (deviceId != null) {
              _clients.remove(deviceId);
              _lastHeartbeat.remove(deviceId); // Clean heartbeat data
              _clientInfo.remove(deviceId);
              _notifyClientCount();
              LogService.instance.registerLog(
                  "Client $deviceId disconnected. Total clients: ${_clients.length}");
            }
          }, onError: (error) {
            // Manage error in connection
            if (deviceId != null) {
              _clients.remove(deviceId);
              _lastHeartbeat.remove(deviceId); // Clean heartbeat data
              _clientInfo.remove(deviceId);
              _notifyClientCount();
              LogService.instance.registerLog(
                  "Error with client $deviceId: $error. Removed from clients.");
            }
          });
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      }
    } catch (e) {
      LogService.instance.registerLog("Failed to start WebSocket Server: $e");
    }
  }

  //TODO: Split startserver into "handleincomingmessage" method to extract the part where we process the message

  Future<void> _registerOrUpdateClient({
    required String deviceId,
    required WebSocket socket,
    required String? remoteIp,
    required NetworkSnapshot? networkSnapshot,
  }) async {
    _clients[deviceId] = socket;
    _lastHeartbeat[deviceId] = DateTime.now();

    final masterSnapshot = await _getMasterNetworkSnapshot();
    final previousInfo = _clientInfo[deviceId];
    final effectiveSnapshot = networkSnapshot ?? previousInfo?.networkSnapshot;
    final networkStatus = NetworkInfoService.compareDeviceNetwork(
      masterSnapshot: masterSnapshot,
      deviceSnapshot: effectiveSnapshot,
      socketRemoteIp: remoteIp,
    );

    _clientInfo[deviceId] = ConnectedDeviceInfo(
      deviceId: deviceId,
      remoteIp: remoteIp ?? previousInfo?.remoteIp,
      networkSnapshot: effectiveSnapshot,
      networkStatus: networkStatus,
      lastSeen: DateTime.now(),
    );

    if (networkStatus == ConnectedDeviceNetworkStatus.wrongNetwork) {
      socket.add(jsonEncode({
        "command": "networkMismatch",
        "message": "This slave is not on the same local network as the master.",
        "masterNetwork": masterSnapshot.toJson(),
      }));
      LogService.instance.registerLog(
          "Slave $deviceId appears to be on the wrong network. remoteIp=$remoteIp "
          "slaveSubnet=${effectiveSnapshot?.effectiveSubnetSignature} "
          "masterSubnet=${masterSnapshot.effectiveSubnetSignature}");
    }

    _notifyClientCount();
  }

  Future<NetworkSnapshot> _getMasterNetworkSnapshot() async {
    try {
      _masterNetworkSnapshot = await NetworkInfoService.getCurrentSnapshot();
    } catch (e) {
      LogService.instance.registerLog("Could not refresh master network: $e");
    }

    return _masterNetworkSnapshot ??
        const NetworkSnapshot(
          isWifiActive: false,
          source: "master-unavailable",
          warnings: ["Master network snapshot unavailable."],
        );
  }

  /// Starts a periodic check for inactive clients based on heartbeat timestamps.
  void _startHeartbeatCheck() {
    _heartbeatCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now();
      final inactiveClients = _lastHeartbeat.keys.where((deviceId) {
        final lastSeen = _lastHeartbeat[deviceId];
        return lastSeen == null ||
            now.difference(lastSeen).inSeconds > inactivityThreshold;
      }).toList();

      for (var deviceId in inactiveClients) {
        _clients.remove(deviceId);
        _lastHeartbeat.remove(deviceId);
        _clientInfo.remove(deviceId);
        LogService.instance
            .registerLog("Client $deviceId removed due to inactivity.");

        // Notify disconnection to callback if defined
        if (onClientRemoved != null) {
          onClientRemoved!(deviceId, inactivityThreshold);
        }
      }

      _notifyClientCount();
    });
  }

  void _stopHeartbeatCheck() {
    _heartbeatCheckTimer?.cancel();
    _heartbeatCheckTimer = null;
  }

  void _notifyClientCount() {
    if (onClientCountChange != null) {
      onClientCountChange!(_clients.length);
    }
  }

  List<String> getConnectedDeviceIds() {
    return _clients.keys.toList();
  }

  List<ConnectedDeviceInfo> getConnectedDeviceInfos() {
    return _clientInfo.values.toList()
      ..sort((a, b) => a.deviceId.compareTo(b.deviceId));
  }

  /// Saves media data locally, either as a photo or video.
  ///
  /// - `binaryData`: The raw binary data of the media file.
  /// - `isPhoto`: Whether the media is a photo (`true`) or a video (`false`).
  /// Returns the file path where the media is saved.
  Future<String> _saveMediaLocally(Uint8List binaryData, bool isPhoto) async {
    LogService.instance.registerLog("Save media locally");

    final directory = await getApplicationDocumentsDirectory();
    //final String sessionDirectoryPath = '${directory.path}/session_${currentSession?.sessionId}'; // TODO: Extract storage manager???
    final String sessionDirectoryPath =
        "${directory.path}/session_${SessionManager.instance.sessionGuid}";
    await Directory(sessionDirectoryPath).create(recursive: true);
    final String fileExtension = binaryData[0] == 0xFF ? "jpg" : "mp4";
    final String filePath =
        "$sessionDirectoryPath/media_${DateTime.now().millisecondsSinceEpoch}.$fileExtension";
    final file = File(filePath);
    await file.writeAsBytes(binaryData);

    if (isPhoto) {
      await GalleryPersistenceService.savePhoto(filePath);
    } else {
      await GalleryPersistenceService.saveVideo(filePath);
    }

    return filePath;
  }

  void startNewSession(String sessionGuid) {
    // Init new session through SessionManager
    SessionManager.instance
        .startSession(sessionGuid, null, deviceType: "Master");

    // Register logs
    LogService.instance
        .registerLog("New capture session started with GUID: $sessionGuid");

    // Notify slaves that session started
    final sessionStartedCommand = jsonEncode({
      "command": "sessionStarted",
      "sessionGuid": sessionGuid,
    });
    sendCommandToAll(sessionStartedCommand);
  }

  /// Sends a command to all connected slave devices.
  void sendCommandToAll(String message) {
    for (var entry in _commandEligibleClients()) {
      entry.value.add(message);
    }
    LogService.instance
        .registerLog("Command sent to all connected slaves: $message");
  }

  Future<void> endCurrentSession() async {
    if (SessionManager.instance.currentSession != null) {
      // Register logs
      LogService.instance.registerLog(
          "Capture session with GUID: ${SessionManager.instance.sessionGuid} ended and stored in history.");

      // End session through SessionManager
      await SessionManager.instance.endSession();

      // Notify slaves that session ended
      final sessionEndedCommand = jsonEncode({
        "command": "sessionEnded",
      });
      sendCommandToAll(sessionEndedCommand);
    } else {
      LogService.instance.registerLog("No active session to end.");
    }
  }

  // TODO: Merge with the sendcommandtoall
  /// Sends a command to one or all connected slaves with optional device id.
  ///
  /// - `command`: The command to send (e.g., `takePhoto`, `startRecordingVideo`).
  /// - `deviceId`: If specified, sends the command to a single device.
  void sendCommand(String command, {String? deviceId}) {
    LogService.instance.registerLog("Sending command $command");

    if (_clients.isEmpty) {
      LogService.instance.registerLog(
          "No slave devices connected. Command '$command' not sent.");
    } else if (deviceId != null && _clients.containsKey(deviceId)) {
      if (_isCommandEligible(deviceId)) {
        _clients[deviceId]?.add(command);
        LogService.instance.registerLog(
            "Command '$command' sent to slave with deviceId: $deviceId.");
      } else {
        LogService.instance.registerLog(
            "Command '$command' blocked for slave $deviceId due to network mismatch.");
      }
    } else {
      for (var entry in _commandEligibleClients()) {
        entry.value.add(command);
      }
      LogService.instance
          .registerLog("Command '$command' sent to all connected slaves.");
    }
  }

  /// Schedules a command to be executed at a specific date and time.
  /// Sends the command along with the timestamp to all connected devices.
  void scheduleCommand(String command, DateTime scheduledTime,
      {String? deviceId}) {
    // Convert the scheduled time to ISO 8601 format for standard communication
    final String scheduledTimeString = scheduledTime.toIso8601String();

    LogService.instance
        .registerLog("Scheduling command '$command' for $scheduledTimeString");

    if (_clients.isEmpty) {
      LogService.instance.registerLog(
          "No slave devices connected. Scheduled command '$command' not sent.");
    } else if (deviceId != null && _clients.containsKey(deviceId)) {
      // Send the scheduled command to a specific slave
      if (_isCommandEligible(deviceId)) {
        _clients[deviceId]?.add(jsonEncode({
          "type": "scheduledCommand",
          "command": command,
          "scheduledTime": scheduledTimeString,
        }));
        LogService.instance.registerLog(
            "Scheduled command '$command' sent to slave with deviceId: $deviceId.");
      } else {
        LogService.instance.registerLog(
            "Scheduled command '$command' blocked for slave $deviceId due to network mismatch.");
      }
    } else {
      // Send the scheduled command to all slaves
      for (var entry in _commandEligibleClients()) {
        entry.value.add(jsonEncode({
          "type": "scheduledCommand",
          "command": command,
          "scheduledTime": scheduledTimeString,
        }));
      }
      LogService.instance.registerLog(
          "Scheduled command '$command' sent to all connected slaves.");
    }
  }

  /// Stops the WebSocket server and cleans up all connections.
  void stopServer() {
    // TODO: Here end active session before stopping server??

    // Clean any client just in case
    for (var client in _clients.values) {
      client.close(WebSocketStatus.normalClosure, "Server shutting down");
    }

    _server?.close();
    _clients.clear();
    _lastHeartbeat.clear(); // Clean heartbeat registry
    _clientInfo.clear();
    _stopHeartbeatCheck(); // Stop timer
    LogService.instance.registerLog("WebSocket Server stopped");
    _notifyClientCount();
  }

  Iterable<MapEntry<String, WebSocket>> _commandEligibleClients() {
    return _clients.entries.where((entry) => _isCommandEligible(entry.key));
  }

  bool _isCommandEligible(String deviceId) {
    final info = _clientInfo[deviceId];
    return info?.networkStatus != ConnectedDeviceNetworkStatus.wrongNetwork;
  }
}
