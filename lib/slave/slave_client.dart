import "dart:async";
import "dart:convert"; // Import for jsonEncode
import "package:camera/camera.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:web_socket_channel/io.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/camera_service.dart";
import "../services/camera_service_singleton.dart";
import "../services/camera_setup_service.dart";
import "../services/device_service.dart"; // Import for device ID service
import "../services/hydracam_api_service.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";
import "../services/session_manager.dart";

abstract class SlaveConnectionClient {
  Stream<String> get statusStream;
  Stream<bool> get connectionStatusStream;
  CameraController? get cameraController;
  Future<void> prepareCameraPreview();
  void connect();
  void disconnect();
}

/// SlaveClient - Handles the WebSocket client for slave devices.
/// This class manages communication with the master device, sending captured media
/// and receiving commands such as "take photo" or "start recording video".
///
/// ### Responsibilities:
/// - Connects to the WebSocket server hosted by the master device.
/// - Sends device-specific data such as its ID and status updates.
/// - Receives and processes commands from the master device.
/// - Captures photos and videos using the `CameraService` and associates them with the active session.
/// - Sends periodic heartbeats to maintain an active connection.
/// - Automatically reconnects in case of a disconnection.

class SlaveClient implements SlaveConnectionClient {
  /// The address of the WebSocket server (master device).
  final String serverAddress;

  /// WebSocket channel for communication with the master.
  IOWebSocketChannel? _channel;

  /// CameraService instance for handling camera operations.
  final CameraService _cameraService;

  /// Flag to indicate whether the client is currently connected.
  bool _isConnected = false;

  /// Flag to track the video recording state.
  bool isRecordingVideo = false;

  /// Timer for automatic reconnection attempts.
  Timer? _reconnectTimer;

  /// Timer for sending periodic heartbeats.
  Timer? _heartbeatTimer;

  /// Device ID for identifying the slave to the master.
  String? _deviceId;

  /// StreamController for broadcasting status updates to the UI.
  final StreamController<String> _statusStreamController =
      StreamController.broadcast();

  /// Stream of status messages for the UI to listen to.
  @override
  Stream<String> get statusStream => _statusStreamController.stream;

  /// StreamController for broadcasting connection status updates to the UI.
  final StreamController<bool> _connectionStatusStreamController =
      StreamController.broadcast();

  /// Stream of connection status updates.
  @override
  Stream<bool> get connectionStatusStream =>
      _connectionStatusStreamController.stream;

  /// Timestamps for photo and video operations.
  DateTime? photoCaptureDate;
  DateTime? videoStartRecordingDate;
  DateTime? videoEndRecordingDate;

  /// CameraController getter for direct access to the camera.
  @override
  CameraController? get cameraController => _cameraService.controller;

  @override
  Future<void> prepareCameraPreview() async {
    try {
      await _cameraService.ensureCameraIsReady();
    } catch (error, stackTrace) {
      LogService.instance.registerLog(
          "Slave camera preview preparation failed: $error\n$stackTrace");
      _statusStreamController.add("Camera preview unavailable: $error");
    }
  }

  /// Callbacks for recording events.
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingStopped;

  /// Callback for scheduled tasks that typically notifies UI to show countdown.
  final Function(String command, DateTime scheduledTime)? onScheduledCommand;
  final Future<Map<String, dynamic>?> Function()? _networkPayloadLoader;

  /// Constructor for `SlaveClient`.
  ///
  /// - `serverAddress`: The WebSocket server address of the master device.
  /// - `serverAddress`: Callback for scheduled tasks that typically notifies UI to show countdown.
  /// - `onPhotoTaken`: Callback for when a photo is captured.
  /// - `onRecordingStarted`: Callback for when video recording starts.
  /// - `onRecordingStopped`: Callback for when video recording stops.
  SlaveClient(
    this.serverAddress, {
    this.onScheduledCommand,
    Function(String)? onPhotoTaken,
    this.onRecordingStarted,
    this.onRecordingStopped,
    @visibleForTesting
    Future<Map<String, dynamic>?> Function()? networkPayloadLoader,
  })  : _networkPayloadLoader = networkPayloadLoader,
        _cameraService = CameraServiceSingleton.instance {
    // Reassign callback after the colon:
    _cameraService.onPhotoTaken = onPhotoTaken;
    // Listener for forced stop:
    CameraServiceSingleton.instance.recordingInterrupted
        .addListener(_handleRecordingInterrupted);
  }

  /// Connects the client to the WebSocket server and initializes communication.
  @override
  Future<void> connect() async {
    if (_isConnected) {
      LogService.instance
          .registerLog("Already connected to WebSocket. Skipping connection.");
      _statusStreamController
          .add("Already connected to WebSocket. Skipping connection.");
      return;
    }

    _deviceId = await DeviceIdService
        .getOrCreateDeviceId(); // Retrieve or create device ID
    _statusStreamController
        .add("Attempting to connect to master at $serverAddress...");
    LogService.instance.registerLog(
        "Attempting to connect to master WebSocket at $serverAddress with Device ID: $_deviceId");

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(serverAddress));

      _isConnected = true;
      _statusStreamController.add("Connected to master at $serverAddress.");
      _connectionStatusStreamController
          .add(true); // Notify UI of connection status

      // Register immediately; the network snapshot follows asynchronously so
      // role switches are not blocked by platform network probes.
      _channel?.sink.add(jsonEncode({
        "type": "deviceId",
        "deviceId": _deviceId,
        "setupStatus": CameraSetupService.instance.buildSetupStatusPayload(),
      }));

      // Also ask status of session
      _channel?.sink.add(jsonEncode({
        "type": "getSessionStatus",
        "deviceId": _deviceId,
      }));
      unawaited(_sendNetworkHeartbeat());

      LogService.instance
          .registerLog("Connected to WebSocket at $serverAddress");

      // Start sending heartbeat messages
      _startHeartbeat();

      _channel?.stream.listen(
        (message) async {
          LogService.instance
              .registerLog("Command received from master: $message");
          _statusStreamController.add("Received command: $message");

          // Check if the message appears to be JSON before attempting to decode it
          if (message.trim().startsWith("{") ||
              message.trim().startsWith("[")) {
            try {
              // Attempt to decode the message as JSON
              final decodedMessage = jsonDecode(message);

              if (decodedMessage is Map<String, dynamic>) {
                // If the decoded message is a Map, process it as a command
                final String? command = decodedMessage["command"];

                if (command == "sessionStarted" || command == "sessionStatus") {
                  LogService.instance.registerLog("Command: $message");
                  final String sessionGuid = decodedMessage["sessionGuid"];
                  LogService.instance.registerLog("Session guid: $sessionGuid");
                  if (sessionGuid.isNotEmpty) {
                    SessionManager.instance.startSession(sessionGuid, null,
                        deviceType: "Slave"); // Store the session
                    notifyReadyToTransmit(sessionGuid);
                  }
                } else if (command == "networkMismatch") {
                  final message = decodedMessage["message"] ??
                      "This device is not on the same network as the master.";
                  LogService.instance.registerLog("Network mismatch: $message");
                  _statusStreamController.add(message.toString());
                } else if (command == "sessionEnded") {
                  // End session
                  await SessionManager.instance.endSession();
                  LogService.instance
                      .registerLog("Session ended as per master command.");
                } else if (command == "noSession") {
                  // No active session on master
                  await SessionManager.instance.endSession();
                  LogService.instance
                      .registerLog("No active session on master.");
                } else {
                  // Process rest of json commands
                  _processCommand(message);
                }
                // Additional JSON-based commands can be handled here
              }
            } catch (e) {
              // Log an error if JSON decoding fails
              LogService.instance
                  .registerLog("Error decoding JSON message: $e");
            }
          } else {
            // Process non-JSON (simple text) messages as specific commands
            _processCommand(message);
          }
        },
        onError: (error) {
          // Handle any errors in the WebSocket connection
          LogService.instance.registerLog("Connection error: $error");
          _statusStreamController.add("Connection error: $error");
          _isConnected = false;
          _connectionStatusStreamController
              .add(false); // Notify UI of connection status
          _stopHeartbeat();
          _attemptReconnect();
        },
        onDone: () {
          // Handle the WebSocket connection closing
          LogService.instance.registerLog("Connection closed");
          _statusStreamController.add("Connection closed.");
          _isConnected = false;
          _connectionStatusStreamController
              .add(false); // Notify UI of connection status
          _stopHeartbeat();
          _attemptReconnect();
        },
      );
    } catch (e) {
      _statusStreamController.add("Failed to connect: $e");
      LogService.instance
          .registerLog("Failed to connect to WebSocket at $serverAddress: $e");
      _isConnected = false;
      _connectionStatusStreamController
          .add(false); // Notify UI of connection status

      // Add a delay before reconnecting to prevent immediate retries on failure
      await Future.delayed(const Duration(seconds: 2));
      _attemptReconnect();
    }
  }

  /// Processes specific commands received from the master.
  /// Gets commands like taking pictures or videos.
  /// This includes scheduled commands for synchronized execution.
  /// Processes specific commands received from the master.
  /// Handles both scheduled commands and immediate commands, whether JSON-based or plain text.
  void _processCommand(String message) async {
    if (message.trim().startsWith("{")) {
      try {
        // Attempt to decode the message as JSON
        final decodedMessage = jsonDecode(message);

        if (decodedMessage is Map<String, dynamic>) {
          final String? type = decodedMessage["type"];
          final String? command = decodedMessage["command"];

          if (type != null && type == "scheduledCommand" && command != null) {
            // Handle scheduled commands
            final DateTime scheduledTime =
                DateTime.parse(decodedMessage["scheduledTime"]);
            _scheduleExecution(command, scheduledTime);
          } else if (type == "sessionStarted" || type == "sessionStatus") {
            // Handle session start/status
            final String sessionGuid = decodedMessage["sessionGuid"];
            SessionManager.instance
                .startSession(sessionGuid, null, deviceType: "Slave");
            notifyReadyToTransmit(sessionGuid);
          } else if (type == "sessionEnded") {
            // Handle session end
            await SessionManager.instance.endSession();
            LogService.instance
                .registerLog("Session ended as per master command.");
          } else if (type == "noSession") {
            // Handle no active session
            await SessionManager.instance.endSession();
            LogService.instance.registerLog("No active session on master.");
          } else {
            // Unknown JSON command type
            LogService.instance.registerLog("Unknown JSON command type: $type");
          }
        } else {
          // If not a JSON message, treat it as a plain text command
          _executeCommand(message);
        }
      } catch (e) {
        // Handle errors in JSON decoding or processing
        LogService.instance.registerLog(
            "Error decoding or processing message in processcommand: $e");
      }
    } else {
      // Not a JSON, continue executing raw command
      _executeCommand(message);
    }
  }

  /// Schedules the execution of a command for a specific time.
  /// This ensures synchronized execution across devices.
  void _scheduleExecution(String command, DateTime scheduledTime) {
    // Find how much time left for scheduled execution
    final Duration delay = scheduledTime.difference(DateTime.now());

    // If we already late, we execute immediately
    if (delay.isNegative) {
      LogService.instance.registerLog(
          "Scheduled time for '$command' has already passed. Executing immediately.");
      _executeCommand(command);
    }
    // Else, we wait until scheduled time and then execute
    else {
      LogService.instance
          .registerLog("Command '$command' scheduled for $scheduledTime.");

      // Notify the UI to handle the countdown
      onScheduledCommand?.call(command, scheduledTime);

      Timer(delay, () => _executeCommand(command));
    }
  }

  /// Executes the received command.
  void _executeCommand(String command) async {
    if (command == "takePhoto") {
      photoCaptureDate = DateTime.now();
      try {
        final photoPath = await _cameraService.takePhoto();
        final receivedDate = DateTime.now();

        // Get the device ID
        final String deviceId = await DeviceIdService.getOrCreateDeviceId();

        // Save the photo locally
        final capturedPhoto = CapturedPhoto(
          photoData: null,
          photoPath: photoPath,
          captureDate: photoCaptureDate!,
          receivedDate: receivedDate,
          slaveDeviceId: deviceId,
          captureContext: _cameraService.lastPhotoCaptureContext,
        );
        SessionManager.instance.addPhoto(capturedPhoto);

        // Update the UI
        _statusStreamController.add("Photo taken and saved locally.");

        // Commented out: Sending to master
        // final file = File(photoPath);
        // final Uint8List photoData = await file.readAsBytes();
        // _channel?.sink.add(jsonEncode({...}));
      } catch (error, stackTrace) {
        LogService.instance
            .registerLog("Slave photo capture failed: $error\n$stackTrace");
        _statusStreamController.add("Photo capture failed: $error");
      }
    } else if (command == "startRecordingVideo") {
      try {
        LogService.instance.registerLog("Starting video recording");
        await _cameraService.startRecordingVideo();
        videoStartRecordingDate = _cameraService.videoStartRecordingDate;
        isRecordingVideo = _cameraService.isRecording;
        if (!isRecordingVideo) {
          throw StateError("Camera service did not enter recording state.");
        }
        onRecordingStarted?.call();
        _statusStreamController.add("Recording video...");
      } catch (error, stackTrace) {
        LogService.instance.registerLog(
            "Slave video recording start failed: $error\n$stackTrace");
        isRecordingVideo = false;
        onRecordingStopped?.call();
        _statusStreamController.add("Recording start failed: $error");
      }
    } else if (command == "stopRecordingVideo") {
      if (!isRecordingVideo) {
        LogService.instance
            .registerLog("Already not recording. Doing nothing.");
        return;
      }

      LogService.instance.registerLog("Stopping video recording");
      try {
        final videoPath = await _cameraService.stopRecordingVideo();
        videoEndRecordingDate = _cameraService.videoEndRecordingDate;
        final startRecordingDate = videoStartRecordingDate;
        final endRecordingDate = videoEndRecordingDate;
        if (startRecordingDate == null || endRecordingDate == null) {
          throw StateError("Slave recording timestamps are missing after stop. "
              "start=$startRecordingDate end=$endRecordingDate");
        }
        final receivedDate = DateTime.now();

        // Get the device ID
        final String deviceId = await DeviceIdService.getOrCreateDeviceId();

        // Save the video locally
        final capturedVideo = CapturedVideo(
          videoData: null,
          videoPath: videoPath,
          slaveDeviceId: deviceId,
          startRecordingDate: startRecordingDate,
          endRecordingDate: endRecordingDate,
          receivedDate: receivedDate,
          captureContext: _cameraService.recordingCaptureContext,
        );
        SessionManager.instance.addVideo(capturedVideo);

        // Update the UI
        _statusStreamController
            .add("Video recording stopped and saved locally.");

        isRecordingVideo = false;
        onRecordingStopped?.call();

        // Commented out: Sending to master
        // final file = File(videoPath);
        // final Uint8List videoData = await file.readAsBytes();
        // _channel?.sink.add(jsonEncode({...}));
      } catch (error, stackTrace) {
        LogService.instance.registerLog(
            "Slave video recording stop failed: $error\n$stackTrace");
        isRecordingVideo = false;
        onRecordingStopped?.call();
        _statusStreamController.add("Recording stop failed: $error");
      }
    } else if (command == "stopCamera") {
      // Stop the camera service when receiving 'stopCamera' command
      _cameraService.stopCamera();
    } else {
      LogService.instance.registerLog("Unknown command received: $command");
    }
  }

  /// Sends a notification to the server that the slave is ready to transmit media.
  Future<bool> notifyReadyToTransmit(String sessionGuid) async {
    final String deviceId = _deviceId ?? "Unknown";

    // Call API service to notify server that device is ready to transmit
    final apiService = HydraCamApiService();
    final bool success =
        await apiService.notifyReadyToTransmit(deviceId, sessionGuid);

    return success;
  }

  /// Notifies the master that recording has been forcibly stopped due to low storage.
  void _notifyMasterForcedStop() {
    if (_channel != null && _isConnected) {
      final message = {
        "type": "forcedStop",
        "deviceId": _deviceId,
        "reason": "storageFull",
      };
      _channel!.sink.add(jsonEncode(message));
      LogService.instance.registerLog("Sent forcedStop notification to master");
    }
  }

  /// A private method to handle forced-stop events from the camera service.
  void _handleRecordingInterrupted() {
    final interrupted =
        CameraServiceSingleton.instance.recordingInterrupted.value;
    if (interrupted) {
      // 1) Update local flag
      isRecordingVideo = false;
      onRecordingStopped
          ?.call(); // So that SlaveScreen will do setState() => no more “Recording…”

      // 2) Notify the Master about forced stop
      _notifyMasterForcedStop();
    }
  }

  /// Starts the periodic heartbeat to maintain the WebSocket connection.
  void _startHeartbeat() {
    _stopHeartbeat(); // Ensure no duplicate timers
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isConnected) {
        await _sendNetworkHeartbeat();
        //LogService.instance.registerLog("Sent heartbeat to master.");
      }
    });
  }

  /// Stops the periodic heartbeat.
  void _stopHeartbeat() {
    if (_heartbeatTimer != null) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  }

  /// Attempts to reconnect to the WebSocket server.
  void _attemptReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return; // Already attempting to reconnect
    }

    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected) {
        LogService.instance
            .registerLog("Attempting to reconnect to master WebSocket...");
        connect();
      } else {
        _reconnectTimer?.cancel();
      }
    });
  }

  @override
  void disconnect() {
    _channel?.sink.close();
    _channel =
        null; // Nullify to ensure a new connection is created on reconnect
    _isConnected = false;
    _connectionStatusStreamController
        .add(false); // Notify UI of connection status
    _reconnectTimer?.cancel();
    _stopHeartbeat();
  }

  Future<Map<String, dynamic>?> _currentNetworkPayload() async {
    try {
      final loader = _networkPayloadLoader;
      if (loader != null) {
        return await loader();
      }
      return (await NetworkInfoService.getCurrentSnapshot()).toJson();
    } catch (e) {
      LogService.instance.registerLog("Could not read slave network info: $e");
      return null;
    }
  }

  Future<void> _sendNetworkHeartbeat() async {
    final networkPayload = await _currentNetworkPayload();
    if (!_isConnected || _deviceId == null) {
      return;
    }
    _channel?.sink.add(jsonEncode({
      "type": "heartbeat",
      "deviceId": _deviceId,
      "timestamp": DateTime.now().toIso8601String(),
      "setupStatus": CameraSetupService.instance.buildSetupStatusPayload(),
      if (networkPayload != null) "network": networkPayload,
    }));
  }
}
