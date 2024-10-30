import 'dart:io';

class MasterServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  Function(int)? onClientCountChange;

  Future<void> startServer() async {
    try {
      _server = await HttpServer.bind('0.0.0.0', 4040);
      print("WebSocket Server successfully started on port 4040");

      await for (HttpRequest request in _server!) {
        print("Received an HTTP request at path: ${request.uri.path}");
        if (request.uri.path == '/ws') {
          print("Attempting to upgrade HTTP request to WebSocket...");
          var socket = await WebSocketTransformer.upgrade(request);
          _clients.add(socket);
          _notifyClientCount();
          print("New WebSocket client connected. Total connected clients: ${_clients.length}");

          socket.listen((data) {
            print("Message received from client: $data");
          }, onDone: () {
            _clients.remove(socket);
            _notifyClientCount();
            print("Client disconnected. Total connected clients: ${_clients.length}");
          });
        } else {
          print("Received a non-WebSocket HTTP request, rejecting...");
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      }
    } catch (e) {
      print("Failed to start WebSocket Server: $e");
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
