import 'dart:async';
import 'package:web_socket_channel/io.dart';
import '../services/camera_service.dart';

/// SlaveClient - WebSocket client on slave devices that listens for master commands and reconnects if disconnected.
class SlaveClient {
  final String serverAddress;
  IOWebSocketChannel? _channel;
  final CameraService _cameraService = CameraService();
  bool _isConnected = false; // Track connection status
  Timer? _reconnectTimer; // Timer for reconnection attempts

  SlaveClient(this.serverAddress);

  /// Connects to the WebSocket server on the master device.
  void connect() {
    _channel = IOWebSocketChannel.connect(Uri.parse(serverAddress));
    _isConnected = true;

    _channel?.stream.listen(
          (message) {
        print("Command received: $message");
        if (message == 'startCamera') {
          _cameraService.startCamera().then((_) {
            // Send confirmation back to the master after starting the camera
            _channel?.sink.add("Photo taken");
            print("Photo taken and confirmation sent to master.");
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
  }

  /// Attempts to reconnect if disconnected.
  void _attemptReconnect() {
    if (_reconnectTimer == null || !_reconnectTimer!.isActive) {
      _reconnectTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        if (!_isConnected) {
          print("Attempting to reconnect...");
          connect();
        } else {
          timer.cancel();
        }
      });
    }
  }

  /// Disconnects from the WebSocket server.
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    _reconnectTimer?.cancel();
  }
}