import 'dart:async';
import 'dart:convert'; // Import for jsonDecode
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../globals.dart';
import '../models/CaptureSession.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/camera_service.dart';
import '../services/log_service.dart';
import '../services/session_manager.dart';

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

class MasterServer {
  HttpServer? _server;
  final Map<String, WebSocket> _clients = {}; // Map to store clients with deviceId as key
  final Map<String, DateTime> _lastHeartbeat = {}; // Track last heartbeat per client
  Timer? _heartbeatCheckTimer; // Timer for checking inactive clients
  // CaptureSession? currentSession; // Current Capture Session is now used in Session Manager Singleton
  List<CaptureSession> sessionHistory = []; // List to store past sessions TODO: EXTRACT TO MANAGER TOO
  Function(int)? onClientCountChange;
  Function(dynamic)? onMediaReceived; // Callback for media reception
  Function(String, int)? onClientRemoved; // Callback for managing slaves disconnecting

  /// Camera service is used for capturing media directly on the master device
  final CameraService cameraService;

  /// Constructor for MasterServer.
  ///
  /// - `cameraService`: The service to handle camera-related operations.
  MasterServer(this.cameraService);


  /// Starts the WebSocket server on the master device and initializes the heartbeat check mechanism.
  /// This method binds to a specific port and listens for incoming connections.
  Future<void> startServer() async {
    try {
      _server = await HttpServer.bind('0.0.0.0', 4040);
      LogService.instance.registerLog("WebSocket Server successfully started on port 4040");

      // Init check to verify inactive clients
      _startHeartbeatCheck();

      await for (HttpRequest request in _server!) {
        if (request.uri.path == '/ws') {
          var socket = await WebSocketTransformer.upgrade(request);
          LogService.instance.registerLog("New WebSocket client connected.");

          String? deviceId;

          // Listen to client messages
          socket.listen((data) async {
            try {
              // Decode message
              final decodedData = jsonDecode(data as String);
              LogService.instance.registerLog("Data received from slave: $decodedData");

              if (decodedData is Map<String, dynamic>) {
                String? messageType = decodedData['type'];
                deviceId = decodedData['deviceId'] ?? 'Unknown';

                // Register client
                if (messageType == 'deviceId') {
                  if (deviceId != null) {
                    _clients[deviceId!] = socket;
                    _notifyClientCount();
                    LogService.instance.registerLog("Registered new slave with deviceId: $deviceId");

                    // After registering the slave, send the session status
                    if (SessionManager.instance.isSessionActive && SessionManager.instance.sessionGuid != null) {
                      // Send session status
                      var sessionStatusMessage = jsonEncode({
                        'command': 'sessionStatus',
                        'sessionGuid': SessionManager.instance.sessionGuid,
                      });

                      // Send the message to the client
                      socket.add(sessionStatusMessage);

                      LogService.instance.registerLog("Sent sessionStatus to $deviceId: $sessionStatusMessage");
                    }
                    else {
                      // No active session
                      var noSessionMessage = jsonEncode({
                        'command': 'noSession',
                      });

                      // Send the message to the client
                      socket.add(noSessionMessage);

                      LogService.instance.registerLog("Sent noSession to $deviceId");
                    }
                  }
                }

                // Receive media
                else if (messageType == 'photo' || messageType == 'video') {
                  // Process media data
                  final Uint8List binaryData = Uint8List.fromList(List<int>.from(decodedData['data']));
                  final String filePath = await _saveMediaLocally(binaryData, messageType == 'photo');
                  final DateTime receivedDate = DateTime.now();

                  if (messageType == 'photo') {
                    final DateTime captureDate = DateTime.parse(decodedData['captureDate']);
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
                    LogService.instance.registerLog("Photo from slave device ($deviceId) received and stored at: $filePath");
                  } else if (messageType == 'video') {
                    final DateTime startRecordingDate = DateTime.parse(decodedData['startRecordingDate']);
                    final DateTime endRecordingDate = DateTime.parse(decodedData['endRecordingDate']);
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
                    LogService.instance.registerLog("Video from slave device ($deviceId) received and stored at: $filePath");
                  }
                }

                // Receive heartbeats from slaves
                else if (messageType == 'heartbeat') {
                  if (deviceId != null) {
                    _lastHeartbeat[deviceId!] = DateTime.now(); // Update last heartbeat
                    LogService.instance.registerLog("Received heartbeat from $deviceId");
                  }
                }

                // Respond to explicit requests on session status
                else if (messageType == 'getSessionStatus') {
                  // Handle getSessionStatus
                  LogService.instance.registerLog("Received getSessionStatus from $deviceId");

                  // Prepare response
                  if (SessionManager.instance.isSessionActive && SessionManager.instance.sessionGuid != null) {
                    // Send session status
                    var sessionStatusMessage = jsonEncode({
                      'command': 'sessionStatus',
                      'sessionGuid': SessionManager.instance.sessionGuid,
                    });

                    // Send the message to the client
                    socket.add(sessionStatusMessage);

                    LogService.instance.registerLog("Sent sessionStatus to $deviceId: $sessionStatusMessage");
                  } else {
                    // No active session
                    var noSessionMessage = jsonEncode({
                      'command': 'noSession',
                    });

                    // Send the message to the client
                    socket.add(noSessionMessage);

                    LogService.instance.registerLog("Sent noSession to $deviceId");
                  }
                }

              } else {
                LogService.instance.registerLog("Unexpected data format received: $data");
              }
            } catch (e) {
              LogService.instance.registerLog("Error decoding data: $e");
            }
          }, onDone: () {
            // Manage client disconnection
            if (deviceId != null) {
              _clients.remove(deviceId);
              _lastHeartbeat.remove(deviceId); // Clean heartbeat data
              _notifyClientCount();
              LogService.instance.registerLog("Client $deviceId disconnected. Total clients: ${_clients.length}");
            }
          }, onError: (error) {
            // Manage error in connection
            if (deviceId != null) {
              _clients.remove(deviceId);
              _lastHeartbeat.remove(deviceId); // Clean heartbeat data
              _notifyClientCount();
              LogService.instance.registerLog("Error with client $deviceId: $error. Removed from clients.");
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

  /// Starts a periodic check for inactive clients based on heartbeat timestamps.
  void _startHeartbeatCheck() {
    _heartbeatCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now();
      final inactiveClients = _lastHeartbeat.keys.where((deviceId) {
        final lastSeen = _lastHeartbeat[deviceId];
        return lastSeen == null || now.difference(lastSeen).inSeconds > inactivityThreshold;
      }).toList();

      for (var deviceId in inactiveClients) {
        _clients.remove(deviceId);
        _lastHeartbeat.remove(deviceId);
        LogService.instance.registerLog("Client $deviceId removed due to inactivity.");

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
        '${directory.path}/session_${SessionManager.instance.sessionGuid}';
    await Directory(sessionDirectoryPath).create(recursive: true);
    final String fileExtension = binaryData[0] == 0xFF ? 'jpg' : 'mp4';
    final String filePath = '$sessionDirectoryPath/media_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    final file = File(filePath);
    await file.writeAsBytes(binaryData);

    // Save to gallery
    if (isPhoto) {
      await GallerySaver.saveImage(filePath, albumName: 'HydraCam/${SessionManager.instance.sessionGuid}');
    } else { // Video
      await GallerySaver.saveVideo(filePath, albumName: 'HydraCam/${SessionManager.instance.sessionGuid}');
    }

    return filePath;
  }

  void startNewSession(String sessionGuid) {
    // Init new session through SessionManager
    SessionManager.instance.startSession(sessionGuid, deviceType: "Master");

    // Register logs
    LogService.instance.registerLog("New capture session started with GUID: $sessionGuid");

    // Notify slaves that session started
    var sessionStartedCommand = jsonEncode({
      'command': 'sessionStarted',
      'sessionGuid': sessionGuid,
    });
    sendCommandToAll(sessionStartedCommand);
  }


  /// Sends a command to all connected slave devices.
  void sendCommandToAll(String message) {
    for (var client in _clients.values) {
      client.add(message);
    }
    LogService.instance.registerLog("Command sent to all connected slaves: $message");
  }


  void endCurrentSession() {
    if (SessionManager.instance.currentSession != null) {
      // Register logs
      LogService.instance.registerLog(
          "Capture session with GUID: ${SessionManager.instance.sessionGuid} ended and stored in history."
      );

      // End session through SessionManager
      SessionManager.instance.endSession();

      // Notify slaves that session ended
      var sessionEndedCommand = jsonEncode({
        'command': 'sessionEnded',
      });
      sendCommandToAll(sessionEndedCommand);

    } else {
      LogService.instance.registerLog("No active session to end.");
    }
  }


  // TODO: Merge with the sendcommandtoall
  /// Sends a command to one or all connected slaves with optional target execution time.
  ///
  /// - `command`: The command to send (e.g., `takePhoto`, `startRecordingVideo`).
  /// - `deviceId`: If specified, sends the command to a single device.
  /// - `targetTime`: An optional future `DateTime` for synchronized execution.
  void sendCommand(String command, {String? deviceId, DateTime? targetTime}) {
    // Prepare the base payload
    final payload = {
      'command': command,
    };

    // If a targetTime is provided, include it in the payload
    if (targetTime != null) {
      payload['timestamp'] = targetTime.toIso8601String();
    }

    // Encode the payload as a JSON string
    final jsonCommand = jsonEncode(payload);

    LogService.instance.registerLog("Sending command: $jsonCommand");

    if (_clients.isEmpty) {
      LogService.instance.registerLog("No slave devices connected. Command '$command' not sent.");
    } else if (deviceId != null && _clients.containsKey(deviceId)) {
      _clients[deviceId]?.add(jsonCommand);
      LogService.instance.registerLog("Command '$command' sent to slave with deviceId: $deviceId.");
    } else {
      for (var client in _clients.values) {
        client.add(jsonCommand);
      }
      LogService.instance.registerLog("Command '$command' sent to all connected slaves.");
    }
  }

  /// Sends a command with optional delay and manages countdown notifications.
  ///
  /// - `command`: The command to send (e.g., `takePhoto`).
  /// - `deviceId`: If specified, sends the command to a single device.
  /// - `targetTime`: The scheduled time for the command to execute.
  /// - `notifyCountdown`: If true, sends a notification to start countdowns.
  void scheduleCommand(
      String command, {
        String? deviceId,
        required DateTime targetTime,
        bool notifyCountdown = true,
      }) {
    // Prepare the base payload
    final payload = {
      'command': command,
      'timestamp': targetTime.toIso8601String(),
    };

    // Encode the payload as JSON
    final jsonCommand = jsonEncode(payload);

    LogService.instance.registerLog("Scheduling command: $jsonCommand");

    // Notify connected slaves
    if (_clients.isEmpty) {
      LogService.instance.registerLog("No slaves connected. Command not sent.");
    } else if (deviceId != null && _clients.containsKey(deviceId)) {
      _clients[deviceId]?.add(jsonCommand);
    } else {
      for (var client in _clients.values) {
        client.add(jsonCommand);
      }
    }

    if (notifyCountdown) {
      _notifyCountdown(targetTime);
    }
  }

  /// Sends a countdown notification to all clients when a command is scheduled.
  void _notifyCountdown(DateTime targetTime) {
    final countdownPayload = {
      'command': 'startCountdown',
      'timestamp': targetTime.toIso8601String(),
    };

    final jsonCountdown = jsonEncode(countdownPayload);

    for (var client in _clients.values) {
      client.add(jsonCountdown);
    }

    LogService.instance.registerLog("Countdown notification sent: $jsonCountdown");
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
    _stopHeartbeatCheck(); // Stop timer
    LogService.instance.registerLog("WebSocket Server stopped");
    _notifyClientCount();
  }


}
