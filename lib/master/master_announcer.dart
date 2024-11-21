import 'dart:io';
import 'dart:async';
import '../services/log_service.dart';

/// MasterAnnouncer - Periodically broadcasts the master device's presence.
/// Sends a UDP message with a unique identifier to allow slave devices to discover its IP.
class MasterAnnouncer {
  static const int broadcastPort = 4041;
  final String message = "MASTER_DISCOVERY"; // Message for master presence
  Timer? _timer;
  bool _isBroadcasting = false; // Flag to track if broadcasting is active

  /// Starts broadcasting the master’s IP periodically using UDP.
  void startBroadcasting() {
    if (_isBroadcasting) {
      LogService.instance.registerLog("MasterAnnouncer is already broadcasting.");
      return;
    }
    _isBroadcasting = true;
    _timer = Timer.periodic(Duration(seconds: 2), (timer) async {
      try{
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        socket.send(message.codeUnits, InternetAddress("255.255.255.255"), broadcastPort);
        if(message != "MASTER_DISCOVERY") LogService.instance.registerLog("Broadcast message sent: $message");
        socket.close();
      }
      catch(e){
        LogService.instance.registerLog("Error during broadcasting: $e");
      }
    });
  }

  /// Stops broadcasting the master’s presence.
  void stopBroadcasting() {
    if (!_isBroadcasting) {
      LogService.instance.registerLog("MasterAnnouncer was not broadcasting.");
      return;
    }
    _isBroadcasting = false;
    _timer?.cancel();
    _timer = null;
    LogService.instance.registerLog("Stopped broadcasting master discovery message.");
  }
}
