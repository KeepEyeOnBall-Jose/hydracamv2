import 'dart:async';
import 'dart:convert'; // Import for jsonEncode
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import '../services/camera_service.dart';
import '../services/device_service.dart'; // Import for device ID service
import 'dart:io';
import '../services/hydracam_api_service.dart';
import '../services/log_service.dart';

class SlaveClient {
  final String serverAddress;
  IOWebSocketChannel? _channel;
  final CameraService _cameraService;
  bool _isConnected = false;
  bool isRecordingVideo = false; // Flag to track video recording state
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer; // Timer for sending heartbeat
  String? _deviceId; // Store the device ID

  // To store timestamps
  DateTime? photoCaptureDate;
  DateTime? videoStartRecordingDate;
  DateTime? videoEndRecordingDate;

  CameraController? get cameraController => _cameraService.controller;

  // Add callbacks
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingStopped;

  SlaveClient(
      this.serverAddress, {
        Function(String)? onPhotoTaken,
        this.onRecordingStarted,
        this.onRecordingStopped,
      }) : _cameraService = CameraService(onPhotoTaken: onPhotoTaken);


  Future<void> connect() async {

    if (_isConnected) {
      LogService.instance.registerLog("Already connected to WebSocket. Skipping connection.");
      return;
    }

    _deviceId = await DeviceIdService.getOrCreateDeviceId(); // Retrieve or create device ID
    LogService.instance.registerLog("Attempting to connect to master WebSocket at $serverAddress with Device ID: $_deviceId");

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(serverAddress));

      _isConnected = true;

      // Send a JSON message containing the device ID after connecting
      _channel?.sink.add(jsonEncode({
        'type': 'deviceId',
        'deviceId': _deviceId,
      }));

      // Also ask status of session
      _channel?.sink.add(jsonEncode({
        'type': 'getSessionStatus',
        'deviceId': _deviceId,
      }));

      LogService.instance.registerLog("Connected to WebSocket at $serverAddress");

      // Start sending heartbeat messages
      _startHeartbeat();

      _channel?.stream.listen(
            (message) {

              LogService.instance.registerLog("Command received from master: $message");

          // Check if the message appears to be JSON before attempting to decode it
          if (message.trim().startsWith('{') || message.trim().startsWith('[')) {
            try {
              // Attempt to decode the message as JSON
              var decodedMessage = jsonDecode(message);

              if (decodedMessage is Map<String, dynamic>) {
                // If the decoded message is a Map, process it as a command
                String? command = decodedMessage['command'];

                if (command == 'sessionStarted') {
                  // Handle session start command and notify readiness
                  String sessionGuid = decodedMessage['sessionGuid'];
                  notifyReadyToTransmit(sessionGuid);
                } else if (command == 'sessionStatus') {
                  // Handle session status command, checking if session GUID is valid
                  String sessionGuid = decodedMessage['sessionGuid'];
                  if (sessionGuid.isNotEmpty) {
                    notifyReadyToTransmit(sessionGuid);
                  }
                }
                // Additional JSON-based commands can be handled here
              }
            } catch (e) {
              // Log an error if JSON decoding fails
              LogService.instance.registerLog("Error decoding JSON message: $e");
            }
          } else {
            // Process non-JSON (simple text) messages as specific commands

            if (message == 'takePhoto') {
              // Capture a photo, timestamp it, and send the data to the master
              photoCaptureDate = DateTime.now();
              _cameraService.takePhoto().then((photoPath) async {
                final file = File(photoPath);
                final Uint8List photoData = await file.readAsBytes();

                // Prepare the data including type, device ID, photo data, and capture timestamp
                final data = {
                  'type': 'photo',
                  'deviceId': _deviceId,
                  'data': photoData,
                  'captureDate': photoCaptureDate!.toIso8601String(),
                };

                // Send serialized photo data to the master
                _channel?.sink.add(jsonEncode(data));
                LogService.instance.registerLog("Real photo data with timestamp and device ID sent to master.");
              });
            } else if (message == 'startRecordingVideo') {
              LogService.instance.registerLog("Starting video recording");
              // Start video recording and log the start timestamp
              videoStartRecordingDate = DateTime.now(); // TODO: USE IN CAMERA SERVICE AND NOT HERE! LIKE WITH MASTER
              _cameraService.startRecordingVideo();
              isRecordingVideo = true;
              onRecordingStarted?.call(); // Notify the UI
              LogService.instance.registerLog("Video recording started at: $videoStartRecordingDate");
            } else if (message == 'stopRecordingVideo') {
              LogService.instance.registerLog("Stopping video recording");
              // Stop video recording, timestamp it, and send video data to the master
              videoEndRecordingDate = DateTime.now();
              _cameraService.stopRecordingVideo().then((videoPath) async {
                final file = File(videoPath);
                final Uint8List videoData = await file.readAsBytes();

                // Prepare the data including type, device ID, video data, and timestamps
                final data = {
                  'type': 'video',
                  'deviceId': _deviceId,
                  'data': videoData,
                  'startRecordingDate': videoStartRecordingDate!.toIso8601String(),
                  'endRecordingDate': videoEndRecordingDate!.toIso8601String(),
                };

                LogService.instance.registerLog("Send video to master");

                // Send serialized video data to the master
                _channel?.sink.add(jsonEncode(data));
                LogService.instance.registerLog("Video data with timestamps and device ID sent to master.");
              });
              isRecordingVideo = false;
              onRecordingStopped?.call(); // Notify the UI
            } else if (message == 'stopCamera') {
              // Stop the camera service when receiving 'stopCamera' command
              _cameraService.stopCamera();
            }
          }
        },
        onError: (error) {
          // Handle any errors in the WebSocket connection
          LogService.instance.registerLog("Connection error: $error");
          _isConnected = false;
          _stopHeartbeat();
          _attemptReconnect();
        },
        onDone: () {
          // Handle the WebSocket connection closing
          LogService.instance.registerLog("Connection closed");
          _isConnected = false;
          _stopHeartbeat();
          _attemptReconnect();
        },
      );

    } catch (e) {
      LogService.instance.registerLog("Failed to connect to WebSocket at $serverAddress: $e");
      _isConnected = false;
      // Add a delay before reconnecting to prevent immediate retries on failure
      await Future.delayed(Duration(seconds: 2));  // <-- This line is added
      _attemptReconnect();
    }
  }

  Future<void> notifyReadyToTransmit(String sessionGuid) async {
    String deviceId = _deviceId ?? 'Unknown';

    // Llama al servicio de API para notificar que el dispositivo está listo
    var apiService = HydraCamApiService();
    bool success = await apiService.notifyReadyToTransmit(deviceId, sessionGuid);

    if (success) {
      LogService.instance.registerLog("Dispositivo notificó al servidor que está listo para transmitir.");
    } else {
      LogService.instance.registerLog("Fallo al notificar al servidor que está listo para transmitir.");
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat(); // Ensure no duplicate timers
    _heartbeatTimer = Timer.periodic(Duration(seconds: 5), (_) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({
          'type': 'heartbeat',
          'deviceId': _deviceId,
          'timestamp': DateTime.now().toIso8601String(),
        }));
        //LogService.instance.registerLog("Sent heartbeat to master.");
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _attemptReconnect() {
    if (_reconnectTimer == null || !_reconnectTimer!.isActive) {
      _reconnectTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        if (!_isConnected) {
          LogService.instance.registerLog("Attempting to reconnect to master WebSocket...");
          connect();
        } else {
          timer.cancel();
        }
      });
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;  // Nullify to ensure a new connection is created on reconnect
    _isConnected = false;
    _reconnectTimer?.cancel();
  }

}
