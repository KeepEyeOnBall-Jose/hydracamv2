import 'dart:io';

/// MasterDiscovery - Listens for master's broadcast message to discover its IP.
/// Calls onMasterDiscovered with the master's IP once discovered.
class MasterDiscovery {
  static const int broadcastPort = 4041;
  final Function(String) onMasterDiscovered;

  MasterDiscovery({required this.onMasterDiscovered});

  /// Listens for the master broadcast message and retrieves the master's IP.
  void startListening() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
    print("Listening for master broadcast on port $broadcastPort...");

    socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
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
}
