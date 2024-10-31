import 'dart:io';
import '../models/CaptureSession.dart';
import '../models/CapturedPhoto.dart';

class MasterServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  CaptureSession? currentSession; // Current Capture Session
  Function(int)? onClientCountChange;
  Function(CapturedPhoto)? onPhotoReceived; // Callback para notificar la recepción de una foto


  Future<void> startServer() async {
    try {
      _server = await HttpServer.bind('0.0.0.0', 4040);
      print("WebSocket Server successfully started on port 4040");

      await for (HttpRequest request in _server!) {
        if (request.uri.path == '/ws') {
          var socket = await WebSocketTransformer.upgrade(request);
          _clients.add(socket);
          _notifyClientCount();
          print("New WebSocket client connected. Total connected clients: ${_clients.length}");

          socket.listen((data) {
            print("Message received from client: $data");
            if (data.startsWith("Real photo taken at path: ")) {
              final photoPath = data.replaceFirst("Real photo taken at path: ", "");
              final receivedPhoto = CapturedPhoto(
                photoPath: photoPath,
                captureDate: DateTime.now(),
                receivedDate: DateTime.now(),
                slaveDeviceId: socket.hashCode.toString(),
              );

              // If there is an active capture session we add the photo to it
              currentSession?.addPhoto(receivedPhoto);
              if (onPhotoReceived != null) {
                onPhotoReceived!(receivedPhoto);
              }
              print("Photo from slave device stored: $photoPath");
            }
          }, onDone: () {
            _clients.remove(socket);
            _notifyClientCount();
            print("Client disconnected. Total connected clients: ${_clients.length}");
          });
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      }
    } catch (e) {
      print("Failed to start WebSocket Server: $e");
    }
  }

  void startNewSession() {
    currentSession = CaptureSession(
      sessionId: DateTime.now().toIso8601String(),
      startTime: DateTime.now(),
    );
    print("New capture session started with ID: ${currentSession?.sessionId}");
  }

  void endCurrentSession() {
    currentSession?.endSession();
    print("Capture session ended at: ${currentSession?.endTime}");
  }

  void sendCommand(String command) {
    if (_clients.isEmpty) {
      print("No slave devices connected. Command '$command' not sent.");
    } else {
      for (var client in _clients) {
        client.add(command);
      }
      print("Command '$command' sent to all connected slaves.");
    }
  }

  void stopServer() {
    _server?.close();
    _clients.clear();
    print("WebSocket Server stopped");
    _notifyClientCount();
  }

  void _notifyClientCount() {
    if (onClientCountChange != null) {
      onClientCountChange!(_clients.length);
    }
  }
}
