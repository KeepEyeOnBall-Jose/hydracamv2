import 'package:web_socket_channel/io.dart';
import '../services/camera_service.dart';

/// SlaveClient - WebSocket client on slave devices that listens for master commands.
class SlaveClient {
  final String serverAddress;
  IOWebSocketChannel? _channel;
  final CameraService _cameraService = CameraService();

  SlaveClient(this.serverAddress);

  /// Connects to the WebSocket server on the master device.
  void connect() {
    _channel = IOWebSocketChannel.connect(Uri.parse(serverAddress));

    _channel?.stream.listen((message) {
      print("Command received: $message");
      if (message == 'startCamera') {
        _cameraService.startCamera();
      } else if (message == 'stopCamera') {
        _cameraService.stopCamera();
      }
    }, onDone: () {
      print("Connection closed");
    });
  }

  /// Disconnects from the WebSocket server.
  void disconnect() {
    _channel?.sink.close();
  }
}
