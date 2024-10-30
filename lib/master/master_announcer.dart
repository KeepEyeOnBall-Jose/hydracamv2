import 'dart:io';
import 'dart:async';

/// MasterAnnouncer - Periodically broadcasts the master device's presence.
/// Sends a UDP message with a unique identifier to allow slave devices to discover its IP.
class MasterAnnouncer {
  static const int broadcastPort = 4041;
  final String message = "MASTER_DISCOVERY"; // Message for master presence
  Timer? _timer;

  /// Starts broadcasting the master’s IP periodically using UDP.
  void startBroadcasting() {
    _timer = Timer.periodic(Duration(seconds: 2), (timer) async {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(message.codeUnits, InternetAddress("255.255.255.255"), broadcastPort);
      print("Broadcast message sent: $message");
      socket.close();
    });
  }

  /// Stops broadcasting the master’s presence.
  void stopBroadcasting() {
    _timer?.cancel();
    print("Stopped broadcasting master discovery message.");
  }
}
