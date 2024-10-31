import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import '../services/camera_service.dart';
import 'dart:io';

class SlaveClient {
  final String serverAddress;
  IOWebSocketChannel? _channel;
  final CameraService _cameraService;
  bool _isConnected = false;
  bool isRecordingVideo = false; // Flag to track video recording state
  Timer? _reconnectTimer;

  // To store timestamps
  DateTime? photoCaptureDate;
  DateTime? videoStartRecordingDate;
  DateTime? videoEndRecordingDate;

  SlaveClient(this.serverAddress, {Function(String)? onPhotoTaken})
      : _cameraService = CameraService(onPhotoTaken: onPhotoTaken);

  void connect() {
    print("Attempting to connect to master WebSocket at $serverAddress");
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(serverAddress));

      _isConnected = true;
      _channel?.sink.add("Slave connected");
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

              // Prepare the data to send, including the timestamp
              final data = {
                'data': photoData,
                'captureDate': photoCaptureDate!.toIso8601String(),
              };
              _channel?.sink.add(data);
              print("Real photo data with timestamp sent to master.");
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

              // Prepare the data to send, including both timestamps
              final data = {
                'data': videoData,
                'startRecordingDate': videoStartRecordingDate!.toIso8601String(),
                'endRecordingDate': videoEndRecordingDate!.toIso8601String(),
              };
              _channel?.sink.add(data);
              print("Video data with timestamps sent to master.");
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
