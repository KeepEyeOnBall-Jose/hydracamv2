import 'dart:io';

/// MasterServer - WebSocket server that runs on the master device.
/// Handles connections with slave devices and sends camera control commands.
class MasterServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];

  /// Starts the WebSocket server on the master device.
  Future<void> startServer() async {
    _server = await HttpServer.bind('0.0.0.0', 4040);
    print("WebSocket Server started on port 4040");

    await for (HttpRequest request in _server!) {
      if (request.uri.path == '/ws') {
        var socket = await WebSocketTransformer.upgrade(request);
        _clients.add(socket);
        print("New client connected");

        socket.listen((data) {
          print("Message received from client: $data");
        }, onDone: () {
          _clients.remove(socket);
          print("Client disconnected");
        });
      }
    }
  }

  /// Sends a command to all connected clients (slave devices).
  /// If no clients are connected, logs a message indicating no slaves are connected.
  /// [command] - The command to send (e.g., 'startCamera', 'stopCamera').
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

  /// Stops the WebSocket server and clears connected clients.
  void stopServer() {
    _server?.close();
    _clients.clear();
    print("WebSocket Server stopped");
  }
}
