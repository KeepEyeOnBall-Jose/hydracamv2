import 'dart:async';
import 'dart:convert'; // Import for jsonEncode
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import '../services/camera_service.dart';
import '../services/device_service.dart'; // Import for device ID service
import 'dart:io';

class SlaveClient {
  final String serverAddress;
  IOWebSocketChannel? _channel;
  final CameraService _cameraService;
  bool _isConnected = false;
  bool isRecordingVideo = false; // Flag to track video recording state
  Timer? _reconnectTimer;
  String? _deviceId; // Store the device ID

  // To store timestamps
  DateTime? photoCaptureDate;
  DateTime? videoStartRecordingDate;
  DateTime? videoEndRecordingDate;

  SlaveClient(this.serverAddress, {Function(String)? onPhotoTaken})
      : _cameraService = CameraService(onPhotoTaken: onPhotoTaken);

  Future<void> connect() async {
    _deviceId = await DeviceIdService.getOrCreateDeviceId(); // Retrieve or create device ID
    print("Attempting to connect to master WebSocket at $serverAddress with Device ID: $_deviceId");

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(serverAddress));

      _isConnected = true;

      // Send a JSON message containing the device ID after connecting
      _channel?.sink.add(jsonEncode({
        'type': 'deviceId',
        'deviceId': _deviceId,
      }));

      print("Connected to WebSocket at $serverAddress");

      _channel?.stream.listen(
            (message) {
          print("Command received from master: $message");
          if (message == 'startCamera') {
            _cameraService.startCamera();
          } else if (message == 'simulateTakePhoto') {
            _channel?.sink.add("Simulated photo taken");
            print("Simulated photo confirmation sent to master.");
          } else if (message == 'takePhoto') {
            photoCaptureDate = DateTime.now(); // Record the capture timestamp
            _cameraService.takePhoto().then((photoPath) async {
              final file = File(photoPath);
              final Uint8List photoData = await file.readAsBytes();

              // Prepare the data to send, including the timestamp and device ID
              final data = {
                'type': 'photo',
                'deviceId': _deviceId,
                'data': photoData,
                'captureDate': photoCaptureDate!.toIso8601String(),
              };
              // Serialize data using jsonEncode
              _channel?.sink.add(jsonEncode(data));
              print("Real photo data with timestamp and device ID sent to master.");
            });
          } else if (message == 'startRecordingVideo') {
            videoStartRecordingDate = DateTime.now(); // Record the start timestamp
            _cameraService.startRecordingVideo();
            isRecordingVideo = true;
            print("Video recording started at: $videoStartRecordingDate");
          } else if (message == 'stopRecordingVideo') {
            videoEndRecordingDate = DateTime.now(); // Record the end timestamp
            _cameraService.stopRecordingVideo().then((videoPath) async {
              final file = File(videoPath);
              final Uint8List videoData = await file.readAsBytes();

              // Prepare the data to send, including the timestamps and device ID
              final data = {
                'type': 'video',
                'deviceId': _deviceId,
                'data': videoData,
                'startRecordingDate': videoStartRecordingDate!.toIso8601String(),
                'endRecordingDate': videoEndRecordingDate!.toIso8601String(),
              };
              // Serialize data using jsonEncode
              _channel?.sink.add(jsonEncode(data));
              print("Video data with timestamps and device ID sent to master.");
            });
            isRecordingVideo = false;
          } else if (message == 'stopCamera') {
            _cameraService.stopCamera();
          }
        },
        onError: (error) {
          print("Connection error: $error");
          _isConnected = false;
          _attemptReconnect();
        },
        onDone: () {
          print("Connection closed");
          _isConnected = false;
          _attemptReconnect();
        },
      );
    } catch (e) {
      print("Failed to connect to WebSocket at $serverAddress: $e");
      _isConnected = false;
      _attemptReconnect();
    }
  }

  void _attemptReconnect() {
    if (_reconnectTimer == null || !_reconnectTimer!.isActive) {
      _reconnectTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        if (!_isConnected) {
          print("Attempting to reconnect to master WebSocket...");
          connect();
        } else {
          timer.cancel();
        }
      });
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    _reconnectTimer?.cancel();
  }
}
