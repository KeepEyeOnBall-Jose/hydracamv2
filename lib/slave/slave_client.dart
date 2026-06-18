import "dart:async";
import "dart:convert"; // Import for jsonEncode
import "package:camera/camera.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:web_socket_channel/io.dart";
import "../constants.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../models/sync_metadata.dart";
import "../services/camera_service.dart";
import "../services/camera_service_singleton.dart";
import "../services/camera_setup_service.dart";
import "../services/device_service.dart"; // Import for device ID service
import "../services/hydracam_api_service.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";
import "../services/scheduled_task_service.dart";
import "../services/session_manager.dart";
import "../services/settings_service.dart";
import "../services/time_sync_service.dart";
import "../services/uploader_service.dart";

abstract class SlaveConnectionClient {
  Stream<String> get statusStream;
  Stream<bool> get connectionStatusStream;
  CameraController? get cameraController;
  Future<void> prepareCameraPreview();
  Future<void> stopRecordingLocally();
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

  /// Optional camera service override for tests.
  final CameraService? _cameraServiceOverride;
  final Function(String)? _onPhotoTaken;
  bool _recordingInterruptListenerRegistered = false;
  CameraService? _recordingInterruptService;

  /// CameraService instance for handling camera operations.
  CameraService get _cameraService {
    final service = _cameraServiceOverride ?? CameraServiceSingleton.instance;
    _registerRecordingInterruptListener(service);
    return service;
  }

  /// Flag to indicate whether the client is currently connected.
  bool _isConnected = false;

  /// Flag to track the video recording state.
  bool isRecordingVideo = false;

  /// Timer for automatic reconnection attempts.
  Timer? _reconnectTimer;

  /// Timer for sending periodic heartbeats.
  Timer? _heartbeatTimer;

  /// Periodic clock re-calibration against the master.
  Timer? _timeSyncTimer;

  /// Safety timer that finalizes a calibration burst if some replies are lost.
  Timer? _timeSyncBurstTimeout;

  /// Monotonically increasing id of the in-flight calibration burst.
  int _activeTimeSyncBurst = 0;

  /// Send timestamps (t0) of outstanding requests in the active burst, keyed by
  /// request id.
  final Map<String, DateTime> _pendingTimeSyncSends = {};

  /// Samples collected so far for the active burst.
  final List<TimeSyncSample> _timeSyncSamples = [];

  final Set<String> _scheduledCommandTaskIds = <String>{};

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
      await _cameraService.prepareCameraPreview();
    } catch (error, stackTrace) {
      LogService.instance.registerLog(
          "Slave camera preview preparation failed: $error\n$stackTrace");
      _statusStreamController.add("Camera preview unavailable: $error");
    }
  }

  @override
  Future<void> stopRecordingLocally() async {
    await _executeCommand("stopRecordingVideo");
  }

  /// Callbacks for recording events.
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingStopped;

  /// Callback for scheduled tasks that typically notifies UI to show countdown.
  final Function(String command, DateTime scheduledTime)? onScheduledCommand;
  final Future<Map<String, dynamic>?> Function()? _networkPayloadLoader;
  final Future<Map<String, dynamic>> Function()? _identityPayloadLoader;
  Future<Map<String, dynamic>>? _identityPayloadFuture;
  final ScheduledTaskService _scheduledTaskService;
  final DateTime Function() _now;

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
    @visibleForTesting
    Future<Map<String, dynamic>> Function()? identityPayloadLoader,
    @visibleForTesting ScheduledTaskService? scheduledTaskService,
    @visibleForTesting CameraService? cameraService,
    @visibleForTesting DateTime Function()? now,
  })  : _networkPayloadLoader = networkPayloadLoader,
        _identityPayloadLoader = identityPayloadLoader,
        _cameraServiceOverride = cameraService,
        _onPhotoTaken = onPhotoTaken,
        _scheduledTaskService =
            scheduledTaskService ?? ScheduledTaskService.instance,
        _now = now ?? DateTime.now {
    if (cameraService != null || CameraServiceSingleton.isInitialized) {
      _registerRecordingInterruptListener(
        cameraService ?? CameraServiceSingleton.instance,
      );
    }
  }

  void _registerRecordingInterruptListener(CameraService service) {
    if (_recordingInterruptListenerRegistered &&
        identical(_recordingInterruptService, service)) {
      return;
    }
    _unregisterRecordingInterruptListener();
    service.onPhotoTaken = _onPhotoTaken;
    service.recordingInterrupted.addListener(_handleRecordingInterrupted);
    _recordingInterruptService = service;
    _recordingInterruptListenerRegistered = true;
  }

  void _unregisterRecordingInterruptListener() {
    final service = _recordingInterruptService;
    if (service == null || !_recordingInterruptListenerRegistered) {
      return;
    }
    service.recordingInterrupted.removeListener(_handleRecordingInterrupted);
    _recordingInterruptService = null;
    _recordingInterruptListenerRegistered = false;
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

      final identityPayload = await _currentIdentityPayload();

      // Register with static app/device identity; the network snapshot follows
      // asynchronously so role switches are not blocked by platform probes.
      _channel?.sink.add(jsonEncode({
        "type": "deviceId",
        "deviceId": _deviceId,
        "sessionGuid": SessionManager.instance.sessionGuid,
        "setupStatus": CameraSetupService.instance.buildSetupStatusPayload(),
        ...identityPayload,
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

      // Begin NTP-style clock calibration against the master.
      _startTimeSync();

      _channel?.stream.listen(
        (message) async {
          // Record the local receive time before any work so the round-trip
          // estimate excludes decode/dispatch latency.
          final DateTime t3 = _now().toUtc();

          // Clock-sync replies arrive in bursts; handle them first and quietly
          // so they do not flood the log or the status stream.
          if (message is String &&
              message.trimLeft().startsWith("{") &&
              message.contains("\"timeSyncResponse\"")) {
            try {
              final decoded = jsonDecode(message);
              if (decoded is Map<String, dynamic> &&
                  decoded["type"] == "timeSyncResponse") {
                _handleTimeSyncResponse(decoded, t3);
                return;
              }
            } catch (_) {
              // Not a usable sync reply; fall through to normal handling.
            }
          }

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
                  _handleSessionAvailableFromMaster(
                    command!,
                    decodedMessage["sessionGuid"],
                  );
                } else if (command == "networkMismatch") {
                  final message = decodedMessage["message"] ??
                      "This device is not on the same network as the master.";
                  LogService.instance.registerLog("Network mismatch: $message");
                  _statusStreamController.add(message.toString());
                } else if (command == "sessionEnded") {
                  await _handleSessionEndedFromMaster(
                    _stringValue(decodedMessage, "sessionGuid"),
                  );
                } else if (command == "noSession") {
                  _handleNoSessionFromMaster();
                } else {
                  // Process rest of json commands
                  await _processCommand(message);
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
            await _processCommand(message);
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
          _stopTimeSync();
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
          _stopTimeSync();
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
  Future<void> _processCommand(String message) async {
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
            _updateClockOffsetFromMasterTime(decodedMessage["masterTime"]);
            await _scheduleExecution(command, scheduledTime);
          } else if (type == "sessionStarted" || type == "sessionStatus") {
            // Handle session start/status
            _handleSessionAvailableFromMaster(
              type!,
              decodedMessage["sessionGuid"],
            );
          } else if (type == "sessionEnded") {
            // Handle session end
            await _handleSessionEndedFromMaster(
              _stringValue(decodedMessage, "sessionGuid"),
            );
          } else if (type == "noSession") {
            _handleNoSessionFromMaster();
          } else if (command == "identifySlave") {
            await _sendIdentifyAck(decodedMessage);
          } else if (command != null) {
            await _executeCommand(command);
          } else {
            // Unknown JSON command type
            LogService.instance.registerLog("Unknown JSON command type: $type");
          }
        } else {
          // If not a JSON message, treat it as a plain text command
          await _executeCommand(message);
        }
      } catch (e) {
        // Handle errors in JSON decoding or processing
        LogService.instance.registerLog(
            "Error decoding or processing message in processcommand: $e");
      }
    } else {
      // Not a JSON, continue executing raw command
      await _executeCommand(message);
    }
  }

  String? _stringValue(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    return value is String ? value : null;
  }

  void _handleSessionAvailableFromMaster(
    String messageType,
    Object? sessionGuidValue,
  ) {
    final sessionGuid =
        sessionGuidValue is String ? sessionGuidValue.trim() : null;
    if (sessionGuid == null || sessionGuid.isEmpty) {
      LogService.instance
          .registerLog("Ignoring $messageType without valid sessionGuid.");
      return;
    }
    LogService.instance.registerLog("Session guid: $sessionGuid");
    _handleSessionAvailable(sessionGuid);
  }

  void _handleSessionAvailable(String sessionGuid) {
    final activeSessionGuid = SessionManager.instance.sessionGuid;
    if (SessionManager.instance.isSessionActive &&
        activeSessionGuid != null &&
        activeSessionGuid.isNotEmpty &&
        activeSessionGuid != sessionGuid) {
      LogService.instance
          .registerLog("Master session conflict: keeping active session "
              "$activeSessionGuid instead of joining $sessionGuid.");
      _statusStreamController
          .add("Master reported a different session. Active session kept.");
      return;
    }

    try {
      SessionManager.instance
          .joinSession(sessionGuid, null, deviceType: "Slave");
    } catch (error) {
      LogService.instance.registerLog(
          "Rejected non-backend session from master: $sessionGuid, error: $error");
      return;
    }
    notifyReadyToTransmit(sessionGuid);
    unawaited(_maybeStartAutoRecordRecording(sessionGuid));
  }

  Future<void> _handleSessionEndedFromMaster(String? endedSessionGuid) async {
    final activeSessionGuid = SessionManager.instance.sessionGuid;
    if (SessionManager.instance.isSessionActive &&
        activeSessionGuid != null &&
        activeSessionGuid.isNotEmpty) {
      final normalizedEndedGuid = endedSessionGuid?.trim();
      if (normalizedEndedGuid == null || normalizedEndedGuid.isEmpty) {
        LogService.instance.registerLog(
            "Ignoring sessionEnded without sessionGuid; active session "
            "$activeSessionGuid kept.");
        _statusStreamController
            .add("Master session end ignored. Active session kept.");
        return;
      }
      if (normalizedEndedGuid != activeSessionGuid) {
        LogService.instance.registerLog(
            "Ignoring sessionEnded for $normalizedEndedGuid; active session "
            "$activeSessionGuid kept.");
        _statusStreamController
            .add("Master ended a different session. Active session kept.");
        return;
      }
    }

    await SessionManager.instance.endSession();
    LogService.instance.registerLog("Session ended as per master command.");
  }

  void _handleNoSessionFromMaster() {
    final activeSessionGuid = SessionManager.instance.sessionGuid;
    if (SessionManager.instance.isSessionActive &&
        activeSessionGuid != null &&
        activeSessionGuid.isNotEmpty) {
      LogService.instance.registerLog(
          "Master reported no active session; keeping active session "
          "$activeSessionGuid until explicit sessionEnded.");
      _statusStreamController
          .add("Master has no active session. Active session kept.");
      return;
    }

    LogService.instance.registerLog("No active session on master.");
    _statusStreamController.add("No active session on master.");
  }

  Future<void> _maybeStartAutoRecordRecording(String sessionGuid) async {
    final enabled = await SettingsService.getAutoRecordMode();
    if (!enabled) {
      return;
    }
    if (_cameraService.isRecording || isRecordingVideo) {
      LogService.instance.registerLog(
          "Auto-record skipped for $sessionGuid because recording is already active.");
      return;
    }

    LogService.instance.registerLog(
        "Auto-record starting recording for active session $sessionGuid.");
    await _executeCommand("startRecordingVideo");
  }

  /// Schedules the execution of a command for a specific time.
  /// This ensures synchronized execution across devices.
  Future<void> _scheduleExecution(
      String command, DateTime scheduledTime) async {
    // Find how much time left for scheduled execution
    final scheduledTasks = _scheduledTaskService;
    final Duration delay = scheduledTasks.delayUntil(scheduledTime);

    // If we already late, we execute immediately
    if (delay.isNegative) {
      LogService.instance.registerLog(
          "Scheduled time for '$command' has already passed. Executing immediately.");
      await _executeCommand(command);
    }
    // Else, we wait until scheduled time and then execute
    else {
      LogService.instance
          .registerLog("Command '$command' scheduled for $scheduledTime.");

      // Notify the UI to handle the countdown
      onScheduledCommand?.call(command, scheduledTime);

      final taskId = "slave:$command:${scheduledTime.toIso8601String()}";
      _scheduledCommandTaskIds.add(taskId);
      unawaited(scheduledTasks
          .scheduleTask(
            taskId,
            scheduledTime,
            () => _executeCommand(command),
          )
          .whenComplete(() => _scheduledCommandTaskIds.remove(taskId)));
    }
  }

  void _cancelScheduledCommands() {
    final taskIds = List<String>.of(_scheduledCommandTaskIds);
    _scheduledCommandTaskIds.clear();
    for (final taskId in taskIds) {
      _scheduledTaskService.cancelTask(taskId);
    }
  }

  void _updateClockOffsetFromMasterTime(Object? masterTimeValue) {
    // The NTP-style handshake is authoritative once it has produced a
    // calibration. The single-sample master timestamp is only a coarse
    // fallback for the very first scheduled command before the first burst
    // completes, so it must not overwrite a measured offset.
    if (TimeSyncService.instance.latest.value != null) {
      return;
    }
    if (masterTimeValue is! String || masterTimeValue.isEmpty) {
      return;
    }

    final masterTime = DateTime.tryParse(masterTimeValue);
    if (masterTime == null) {
      LogService.instance
          .registerLog("Ignoring invalid master clock time: $masterTimeValue");
      return;
    }

    final offset = masterTime.difference(_now());
    _scheduledTaskService.updateClockOffset(offset);
    LogService.instance.registerLog(
        "Applied coarse fallback clock offset from master timestamp: "
        "${offset.inMilliseconds} ms.");
  }

  /// Executes the received command.
  Future<void> _executeCommand(String command) async {
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
          syncMetadata: _syncMetadataAt(photoCaptureDate!),
        );
        await SessionManager.instance.addPhoto(capturedPhoto);

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
          syncMetadata: _syncMetadataAt(startRecordingDate),
        );
        await SessionManager.instance.addVideo(capturedVideo);

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
    } else if (command == "identifySlave") {
      await _sendIdentifyAck();
    } else if (command == "startUploadingAll") {
      LogService.instance
          .registerLog("Start-upload-all command received from master.");
      _statusStreamController.add("Starting queued uploads...");
      await UploaderService().startUploadingManually();
    } else {
      LogService.instance.registerLog("Unknown command received: $command");
    }
  }

  Future<void> _sendIdentifyAck([Map<String, dynamic>? request]) async {
    if (_channel == null || !_isConnected) {
      return;
    }

    final networkPayload = await _currentNetworkPayload();
    final identityPayload = await _currentIdentityPayload();
    final sessionMediaPayload = _sessionMediaPayload();
    final channel = _channel;
    if (channel == null || !_isConnected) {
      LogService.instance.registerLog(
          "Skipping identifyAck because slave disconnected before payload was ready.");
      return;
    }
    final payload = {
      "type": "identifyAck",
      "deviceId": _deviceId,
      "requestId": request?["requestId"],
      "status": "alive",
      "sessionGuid": SessionManager.instance.sessionGuid,
      "timestamp": DateTime.now().toIso8601String(),
      "setupStatus": CameraSetupService.instance.buildSetupStatusPayload(),
      if (sessionMediaPayload != null) "sessionMedia": sessionMediaPayload,
      ...identityPayload,
      if (networkPayload != null) "network": networkPayload,
    };
    channel.sink.add(jsonEncode(payload));
    LogService.instance.registerLog("Sent identifyAck notification to master");
    _statusStreamController.add("Identify acknowledged to master.");
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
    final interrupted = _cameraService.recordingInterrupted.value;
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

  /// Snapshot of the current clock calibration for a capture at instant [at],
  /// or null if the device has never synchronized.
  SyncMetadata? _syncMetadataAt(DateTime at) =>
      TimeSyncService.instance.latest.value?.toSyncMetadata(at);

  /// Starts NTP-style clock calibration: one burst immediately, then on a timer.
  void _startTimeSync() {
    _stopTimeSync();
    _sendTimeSyncBurst();
    _timeSyncTimer = Timer.periodic(
      const Duration(seconds: timeSyncIntervalSeconds),
      (_) => _sendTimeSyncBurst(),
    );
  }

  /// Cancels calibration timers and clears any in-flight burst state.
  void _stopTimeSync() {
    _timeSyncTimer?.cancel();
    _timeSyncTimer = null;
    _timeSyncBurstTimeout?.cancel();
    _timeSyncBurstTimeout = null;
    _pendingTimeSyncSends.clear();
    _timeSyncSamples.clear();
  }

  /// Fires a burst of [timeSyncSampleCount] clock-sync probes at the master.
  void _sendTimeSyncBurst() {
    if (!_isConnected || _deviceId == null || _channel == null) {
      return;
    }

    final burstId = ++_activeTimeSyncBurst;
    _pendingTimeSyncSends.clear();
    _timeSyncSamples.clear();

    for (var seq = 0; seq < timeSyncSampleCount; seq++) {
      final id = "$burstId:$seq";
      final t0 = _now().toUtc();
      _pendingTimeSyncSends[id] = t0;
      _channel?.sink.add(jsonEncode({
        "type": "timeSyncRequest",
        "deviceId": _deviceId,
        "id": id,
        "t0": t0.toIso8601String(),
      }));
    }

    _timeSyncBurstTimeout?.cancel();
    _timeSyncBurstTimeout = Timer(
      const Duration(seconds: 3),
      () => _finalizeTimeSyncBurst(burstId),
    );
  }

  /// Matches a master reply to its outstanding request, builds a sample, and
  /// finalizes the burst once every probe has been answered.
  void _handleTimeSyncResponse(Map<String, dynamic> decoded, DateTime t3) {
    final id = decoded["id"]?.toString();
    if (id == null) {
      return;
    }
    final t0 = _pendingTimeSyncSends[id];
    if (t0 == null) {
      // Stale reply from a previous burst, or unknown id.
      return;
    }
    final t1Raw = decoded["t1"];
    final t2Raw = decoded["t2"];
    final t1 = t1Raw is String ? DateTime.tryParse(t1Raw) : null;
    final t2 = t2Raw is String ? DateTime.tryParse(t2Raw) : null;
    if (t1 == null || t2 == null) {
      return;
    }
    _pendingTimeSyncSends.remove(id);

    _timeSyncSamples.add(
      TimeSyncService.computeSample(t0: t0, t1: t1, t2: t2, t3: t3),
    );

    if (_timeSyncSamples.length >= timeSyncSampleCount) {
      _finalizeTimeSyncBurst(_activeTimeSyncBurst);
    }
  }

  /// Aggregates the collected samples for [burstId] and applies the calibration.
  void _finalizeTimeSyncBurst(int burstId) {
    if (burstId != _activeTimeSyncBurst) {
      return; // Already finalized or superseded by a newer burst.
    }
    _timeSyncBurstTimeout?.cancel();
    _timeSyncBurstTimeout = null;

    final samples = List<TimeSyncSample>.of(_timeSyncSamples);
    _timeSyncSamples.clear();
    _pendingTimeSyncSends.clear();
    // Bump so any late replies or the cancelled timeout cannot finalize again.
    _activeTimeSyncBurst++;

    final result =
        TimeSyncService.aggregate(samples, calibratedAt: _now().toUtc());
    if (result == null) {
      LogService.instance
          .registerLog("Clock sync burst produced no usable samples.");
      return;
    }

    TimeSyncService.instance.record(result);
    _scheduledTaskService.updateClockOffset(result.offset);
    LogService.instance.registerLog(
        "Clock synced to master: offset ${result.offset.inMilliseconds} ms, "
        "uncertainty ${result.uncertainty.inMilliseconds} ms, "
        "RTT ${result.minRoundTrip.inMilliseconds} ms, "
        "${result.sampleCount} samples, ${result.confidence.name}.");
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
    _stopTimeSync();
    _cancelScheduledCommands();
    _unregisterRecordingInterruptListener();
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

  Future<Map<String, dynamic>> _currentIdentityPayload() {
    return _identityPayloadFuture ??= _loadIdentityPayload();
  }

  Future<Map<String, dynamic>> _loadIdentityPayload() async {
    final loader = _identityPayloadLoader;
    if (loader != null) {
      return await loader();
    }

    final payload = <String, dynamic>{};

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _putIfNonBlank(payload, "appVersion", packageInfo.version);
      _putIfNonBlank(payload, "appBuildNumber", packageInfo.buildNumber);
    } catch (e) {
      LogService.instance
          .registerLog("Could not read slave app version diagnostics: $e");
    }

    try {
      final deviceInfo = await DeviceIdService.getDeviceInfo();
      _putIfNonBlank(
        payload,
        "hardware",
        _hardwareLabelFromDeviceInfo(deviceInfo),
      );
    } catch (e) {
      LogService.instance
          .registerLog("Could not read slave hardware diagnostics: $e");
    }

    return payload;
  }

  void _putIfNonBlank(
    Map<String, dynamic> payload,
    String key,
    Object? value,
  ) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) {
      payload[key] = text;
    }
  }

  String? _hardwareLabelFromDeviceInfo(Map<String, dynamic> deviceInfo) {
    return _firstNonBlank([
      deviceInfo["modelName"],
      deviceInfo["model"],
      deviceInfo["name"],
      deviceInfo["platform"],
    ]);
  }

  String? _firstNonBlank(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  Future<void> _sendNetworkHeartbeat() async {
    final networkPayload = await _currentNetworkPayload();
    final identityPayload = await _currentIdentityPayload();
    if (!_isConnected || _deviceId == null) {
      return;
    }
    final sessionMediaPayload = _sessionMediaPayload();
    _channel?.sink.add(jsonEncode({
      "type": "heartbeat",
      "deviceId": _deviceId,
      "sessionGuid": SessionManager.instance.sessionGuid,
      "timestamp": DateTime.now().toIso8601String(),
      "setupStatus": CameraSetupService.instance.buildSetupStatusPayload(),
      if (sessionMediaPayload != null) "sessionMedia": sessionMediaPayload,
      ...identityPayload,
      if (networkPayload != null) "network": networkPayload,
    }));
  }

  Map<String, int>? _sessionMediaPayload() {
    final session = SessionManager.instance.currentSession;
    if (session == null) {
      return null;
    }

    final photos = session.capturedPhotos;
    final videos = session.capturedVideos;
    final uploadedPhotoCount = photos.where((photo) => photo.isUploaded).length;
    final uploadedVideoCount = videos.where((video) => video.isUploaded).length;
    final mediaCount = photos.length + videos.length;
    final uploadedCount = uploadedPhotoCount + uploadedVideoCount;

    return {
      "photoCount": photos.length,
      "videoCount": videos.length,
      "pendingUploadCount": mediaCount - uploadedCount,
      "uploadedCount": uploadedCount,
    };
  }
}
