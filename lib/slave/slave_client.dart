import 'dart:async';
import 'package:web_socket_channel/io.dart';
import '../services/camera_service.dart';

class SlaveClient {
  final String serverAddress;
  IOWebSocketChannel? _channel;
  final CameraService _cameraService;
  bool _isConnected = false;
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
            _cameraService.takePhoto().then((photoPath) {
              _channel?.sink.add("Real photo taken at path: $photoPath");
              print("Real photo taken and confirmation sent to master.");
            });
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
