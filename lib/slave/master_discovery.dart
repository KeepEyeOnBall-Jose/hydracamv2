import 'dart:io';

/// MasterDiscovery - Listens for master's broadcast message to discover its IP.
/// Calls onMasterDiscovered with the master's IP once discovered.
class MasterDiscovery {
  static const int broadcastPort = 4041;
  final Function(String) onMasterDiscovered;
  RawDatagramSocket? _socket; // Store the socket as a member variable

  MasterDiscovery({required this.onMasterDiscovered});

  /// Starts listening for the master broadcast message.
  Future<void> startListening() async {
    // Close any existing socket before creating a new one
    await stopListening();

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
    print("Listening for master broadcast on port $broadcastPort...");

    _socket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket?.receive();
        if (datagram != null) {
          final message = String.fromCharCodes(datagram.data);
          print("Received broadcast message: $message from ${datagram.address.address}");
          if (message == "MASTER_DISCOVERY") {
            final masterIp = datagram.address.address;
            print("Master discovered at IP: $masterIp");
            onMasterDiscovered(masterIp);
          }
        }
      }
    });
  }

  /// Stops listening for the master broadcast message and closes the socket.
  Future<void> stopListening() async {
    if (_socket != null) {
      _socket?.close();
      _socket = null;
      print("Stopped listening for master broadcast.");
    }
  }
}
