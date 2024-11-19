import 'dart:async';
import 'dart:convert'; // Import for jsonDecode
import 'dart:io';
import 'dart:typed_data';
import '../models/CaptureSession.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';

class MasterServer {
  static const int inactivityThreshold = 5; // Inactivity time before disconnecting slave client in seconds
  HttpServer? _server;
  final Map<String, WebSocket> _clients = {}; // Map to store clients with deviceId as key
  final Map<String, DateTime> _lastHeartbeat = {}; // Track last heartbeat per client
  Timer? _heartbeatCheckTimer; // Timer for checking inactive clients
  CaptureSession? currentSession; // Current Capture Session
  List<CaptureSession> sessionHistory = []; // List to store past sessions
  Function(int)? onClientCountChange;
  Function(dynamic)? onMediaReceived; // Callback for media reception
  Function(String, int)? onClientRemoved; // Callback for managing slaves disconnecting

  Future<void> startServer() async {
    try {
      _server = await HttpServer.bind('0.0.0.0', 4040);
      print("WebSocket Server successfully started on port 4040");

      // Init check to verify inactive clients
      _startHeartbeatCheck();

      await for (HttpRequest request in _server!) {
        if (request.uri.path == '/ws') {
          var socket = await WebSocketTransformer.upgrade(request);
          print("New WebSocket client connected.");

          String? deviceId;

          // Listen to client messages
          socket.listen((data) async {
            try {
              // Decode message
              final decodedData = jsonDecode(data as String);
              print("Data received from slave: $decodedData");

              if (decodedData is Map<String, dynamic>) {
                String? messageType = decodedData['type'];
                deviceId = decodedData['deviceId'] ?? 'Unknown';

                // Register client
                if (messageType == 'deviceId') {
                  if (deviceId != null) {
                    _clients[deviceId!] = socket;
                    _notifyClientCount();
                    print("Registered new slave with deviceId: $deviceId");
                  }
                } else if (messageType == 'heartbeat') {
                  if (deviceId != null) {
                    _lastHeartbeat[deviceId!] = DateTime.now(); // Update last heartbeat
                    print("Received heartbeat from $deviceId");
                  }
                }
              } else {
                print("Unexpected data format received: $data");
              }
            } catch (e) {
              print("Error decoding data: $e");
            }
          }, onDone: () {
            // Manage client disconnection
            if (deviceId != null) {
              _clients.remove(deviceId);
              _lastHeartbeat.remove(deviceId); // Clean heartbeat data
              _notifyClientCount();
              print("Client $deviceId disconnected. Total clients: ${_clients.length}");
            }
          }, onError: (error) {
            // Manage error in connection
            if (deviceId != null) {
              _clients.remove(deviceId);
              _lastHeartbeat.remove(deviceId); // Clean heartbeat data
              _notifyClientCount();
              print("Error with client $deviceId: $error. Removed from clients.");
            }
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
  void _startHeartbeatCheck() {
    _heartbeatCheckTimer = Timer.periodic(Duration(seconds: 10), (_) {
      final now = DateTime.now();
      final inactiveClients = _lastHeartbeat.keys.where((deviceId) {
        final lastSeen = _lastHeartbeat[deviceId];
        return lastSeen == null || now.difference(lastSeen).inSeconds > inactivityThreshold;
      }).toList();

      for (var deviceId in inactiveClients) {
        _clients.remove(deviceId);
        _lastHeartbeat.remove(deviceId);
        print("Client $deviceId removed due to inactivity.");

        // Notify disconnection to callback if defined
        if (onClientRemoved != null) {
          onClientRemoved!(deviceId, inactivityThreshold);
        }
      }

      _notifyClientCount();
    });
  }

  void _stopHeartbeatCheck() {
    _heartbeatCheckTimer?.cancel();
    _heartbeatCheckTimer = null;
  }



  void _notifyClientCount() {
    if (onClientCountChange != null) {
      onClientCountChange!(_clients.length);
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
    _lastHeartbeat.clear(); // Clean heartbeat registry
    _stopHeartbeatCheck(); // Stop timer
    print("WebSocket Server stopped");
    _notifyClientCount();
  }


}
