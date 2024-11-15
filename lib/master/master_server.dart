import 'dart:convert'; // Import for jsonDecode
import 'dart:io';
import 'dart:typed_data';
import '../models/CaptureSession.dart';
import '../models/CapturedPhoto.dart';
import 'package:path_provider/path_provider.dart';
import '../models/CapturedVideo.dart';
import 'package:gallery_saver/gallery_saver.dart';

class MasterServer {
  HttpServer? _server;
  final Map<String, WebSocket> _clients = {}; // Map to store clients with deviceId as key
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
          print("New WebSocket client connected.");

          socket.listen((data) async {
            try {
              // Try decode JSON
              final decodedData = jsonDecode(data as String);
              print("Data received from slave: $decodedData");

              if (decodedData is Map<String, dynamic>) {
                String? messageType = decodedData['type'];
                String deviceId = decodedData['deviceId'] ?? 'Unknown';

                // Manage each type of message
                if (messageType == 'getSessionStatus') {
                  String deviceId = decodedData['deviceId'] ?? 'Unknown';
                  var sessionStatusResponse = jsonEncode({
                    'command': 'sessionStatus',
                    'sessionGuid': currentSession?.sessionGuid ?? '',
                  });
                  socket.add(sessionStatusResponse);
                }


                if (messageType == 'deviceId') {
                  // Register client with deviceId
                  _clients[deviceId] = socket;
                  _notifyClientCount();
                  print("Registered new slave with deviceId: $deviceId");
                } else if (messageType == 'photo' || messageType == 'video') {
                  // Process media data
                  final Uint8List binaryData = Uint8List.fromList(List<int>.from(decodedData['data']));
                  final String filePath = await _saveMediaLocally(binaryData, messageType == 'photo');
                  final DateTime receivedDate = DateTime.now();

                  if (messageType == 'photo') {
                    final DateTime captureDate = DateTime.parse(decodedData['captureDate']);
                    final receivedPhoto = CapturedPhoto(
                      photoData: null,
                      photoPath: filePath,
                      captureDate: captureDate,
                      receivedDate: receivedDate,
                      slaveDeviceId: deviceId,
                    );
                    currentSession?.addPhoto(receivedPhoto);
                    onMediaReceived?.call(receivedPhoto);
                    print("Photo from slave device ($deviceId) received and stored at: $filePath");
                  } else if (messageType == 'video') {
                    final DateTime startRecordingDate = DateTime.parse(decodedData['startRecordingDate']);
                    final DateTime endRecordingDate = DateTime.parse(decodedData['endRecordingDate']);
                    final receivedVideo = CapturedVideo(
                      videoData: null,
                      videoPath: filePath,
                      slaveDeviceId: deviceId,
                      startRecordingDate: startRecordingDate,
                      endRecordingDate: endRecordingDate,
                      receivedDate: receivedDate,
                    );
                    currentSession?.addVideo(receivedVideo);
                    onMediaReceived?.call(receivedVideo);
                    print("Video from slave device ($deviceId) received and stored at: $filePath");
                  }
                } else {
                  print("Unexpected message type: $messageType");
                }
              } else {
                print("Unexpected data format received: $data");
              }
            } catch (e) {
              print("Error decoding data or handling media: $e");
            }
          }, onDone: () {
            // Delete client on disconnect
            _clients.removeWhere((key, value) => value == socket);
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

  List<String> getConnectedDeviceIds() {
    return _clients.keys.toList();
  }

  Future<String> _saveMediaLocally(Uint8List binaryData, bool isPhoto) async {
    final directory = await getApplicationDocumentsDirectory();
    final String sessionDirectoryPath = '${directory.path}/session_${currentSession?.sessionId}';
    await Directory(sessionDirectoryPath).create(recursive: true);
    final String fileExtension = binaryData[0] == 0xFF ? 'jpg' : 'mp4';
    final String filePath = '$sessionDirectoryPath/media_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    final file = File(filePath);
    await file.writeAsBytes(binaryData);

    // Save to gallery
    if (isPhoto) {
      await GallerySaver.saveImage(filePath, albumName: 'HydraCam/${currentSession?.sessionId}');
    } else {
      await GallerySaver.saveVideo(filePath, albumName: 'HydraCam/${currentSession?.sessionId}');
    }

    return filePath;
  }

  void startNewSession(String? sessionGuid) {
    var currentDate = DateTime.now();
    currentSession = CaptureSession(
      sessionId: currentDate.toIso8601String(),
      startTime: currentDate,
    );
    print("New capture session started with ID: ${currentSession?.sessionId}");

    // Notify slaves that session has started
    var sessionStartedCommand = jsonEncode({
      'command': 'sessionStarted',
      'sessionGuid': sessionGuid,
    });
    sendCommandToAll(sessionStartedCommand);

    // update guid on current session
    currentSession!.sessionGuid = sessionGuid;
  }

  void sendCommandToAll(String message) {
    for (var client in _clients.values) {
      client.add(message);
    }
    print("Command sent to all connected slaves: $message");
  }


  void endCurrentSession() {
    if (currentSession != null) {
      sessionHistory.add(currentSession!);
      currentSession?.endSession();
      currentSession = null;
      print("Capture session ended and stored in history.");
    }
  }

  void sendCommand(String command, {String? deviceId}) {
    if (_clients.isEmpty) {
      print("No slave devices connected. Command '$command' not sent.");
    } else if (deviceId != null && _clients.containsKey(deviceId)) {
      _clients[deviceId]?.add(command);
      print("Command '$command' sent to slave with deviceId: $deviceId.");
    } else {
      for (var client in _clients.values) {
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
