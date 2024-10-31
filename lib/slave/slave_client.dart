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
            _cameraService.takePhoto().then((photoPath) async {
              final file = File(photoPath);
              final Uint8List photoData = await file.readAsBytes();
              _channel?.sink.add(photoData);
              print("Real photo data sent to master.");
            });
          } else if (message == 'startRecordingVideo') {
            _cameraService.startRecordingVideo();
            isRecordingVideo = true;
            print("Video recording started");
          } else if (message == 'stopRecordingVideo') {
            _cameraService.stopRecordingVideo().then((videoPath) async {
              final file = File(videoPath);
              final Uint8List videoData = await file.readAsBytes();
              _channel?.sink.add(videoData);
              print("Video data sent to master.");
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
