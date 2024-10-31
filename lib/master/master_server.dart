import 'dart:io';
import 'dart:typed_data';
import '../models/CaptureSession.dart';
import '../models/CapturedPhoto.dart';
import 'package:path_provider/path_provider.dart';

class MasterServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  CaptureSession? currentSession; // Current Capture Session
  List<CaptureSession> sessionHistory = []; // List to store past sessions
  Function(int)? onClientCountChange;
  Function(CapturedPhoto)? onPhotoReceived; // Callback to notify we received a photo


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

          socket.listen((data) async {
            if (data is List<int>) {
              // Received binary data
              final Uint8List binaryData = Uint8List.fromList(data);
              final String filePath = await _savePhotoLocally(binaryData);

              // Create CapturedPhoto with binary data set to null after saving
              final receivedPhoto = CapturedPhoto(
                photoData: null, // Clear binary data to free memory
                photoPath: filePath,
                captureDate: DateTime.now(),
                receivedDate: DateTime.now(),
                slaveDeviceId: socket.hashCode.toString(),
              );

              // If there is an active capture session, add the photo to it
              currentSession?.addPhoto(receivedPhoto);
              if (onPhotoReceived != null) {
                onPhotoReceived!(receivedPhoto);
              }
              print("Photo from slave device received and stored at: $filePath");
            } else {
              print("Non-binary message received: $data");
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

  Future<String> _savePhotoLocally(Uint8List binaryData) async {
    // Get the application documents directory
    final directory = await getApplicationDocumentsDirectory();
    final String sessionDirectoryPath = '${directory.path}/session_${currentSession?.sessionId}';
    await Directory(sessionDirectoryPath).create(recursive: true);

    // Create a unique file path for the photo
    final String filePath = '$sessionDirectoryPath/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(filePath);
    await file.writeAsBytes(binaryData);
    return filePath;
  }

  void startNewSession() {
    var currentDate = DateTime.now();
    currentSession = CaptureSession(
      sessionId: currentDate.toIso8601String(),
      startTime: currentDate,
    );
    print("New capture session started with ID: ${currentSession?.sessionId}");
  }

  void endCurrentSession() {
    if (currentSession != null) {
      sessionHistory.add(currentSession!);
      currentSession?.endSession();
      currentSession = null;
      print("Capture session ended and stored in history.");
    }
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
