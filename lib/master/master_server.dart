import 'dart:convert'; // Import for jsonDecode
import 'dart:io';
import 'dart:typed_data';
import '../models/CaptureSession.dart';
import '../models/CapturedPhoto.dart';
import 'package:path_provider/path_provider.dart';
import '../models/CapturedVideo.dart';

class MasterServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  CaptureSession? currentSession; // Current Capture Session
  List<CaptureSession> sessionHistory = []; // List to store past sessions
  Function(int)? onClientCountChange;
  Function(dynamic)? onMediaReceived; // Callback for media reception

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
            try {
              // Attempt to decode the data as JSON
              final decodedData = jsonDecode(data as String);
              print("Data received from slave: $decodedData");

              if (decodedData is Map<String, dynamic>) {
                // Convert List<dynamic> to List<int>
                final Uint8List binaryData = Uint8List.fromList(List<int>.from(decodedData['data']));
                final String filePath = await _saveMediaLocally(binaryData);
                final DateTime receivedDate = DateTime.now();

                if (filePath.endsWith('.jpg')) {
                  // Parse captureDate from string
                  final DateTime captureDate = DateTime.parse(decodedData['captureDate']);

                  final receivedPhoto = CapturedPhoto(
                    photoData: null,
                    photoPath: filePath,
                    captureDate: captureDate,
                    receivedDate: receivedDate,
                    slaveDeviceId: socket.hashCode.toString(),
                  );
                  currentSession?.addPhoto(receivedPhoto);
                  onMediaReceived?.call(receivedPhoto);
                  print("Photo from slave device received and stored at: $filePath");

                } else if (filePath.endsWith('.mp4')) {
                  // Parse startRecordingDate and endRecordingDate from strings
                  final DateTime startRecordingDate = DateTime.parse(decodedData['startRecordingDate']);
                  final DateTime endRecordingDate = DateTime.parse(decodedData['endRecordingDate']);

                  final receivedVideo = CapturedVideo(
                    videoData: null,
                    videoPath: filePath,
                    slaveDeviceId: socket.hashCode.toString(),
                    startRecordingDate: startRecordingDate,
                    endRecordingDate: endRecordingDate,
                    receivedDate: receivedDate,
                  );
                  currentSession?.addVideo(receivedVideo);
                  onMediaReceived?.call(receivedVideo);
                  print("Video from slave device received and stored at: $filePath");
                }
              } else {
                print("Unexpected data format received: $data");
              }
            } catch (e) {
              print("Error decoding data or handling media: $e");
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

  Future<String> _saveMediaLocally(Uint8List binaryData) async {
    final directory = await getApplicationDocumentsDirectory();
    final String sessionDirectoryPath = '${directory.path}/session_${currentSession?.sessionId}';
    await Directory(sessionDirectoryPath).create(recursive: true);
    final String fileExtension = binaryData[0] == 0xFF ? 'jpg' : 'mp4';
    final String filePath = '$sessionDirectoryPath/media_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
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
