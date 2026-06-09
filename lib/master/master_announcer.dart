import "dart:async";
import "dart:io";

import "../services/log_service.dart";

typedef MasterBroadcastSender = FutureOr<void> Function(
  String message,
  int port,
);

typedef MasterAnnouncerTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer timer) callback,
);

/// MasterAnnouncer - Periodically broadcasts the master device's presence.
/// Sends a UDP message with a unique identifier to allow slave devices to discover its IP.
class MasterAnnouncer {
  static const int broadcastPort = 4041;
  static const String discoveryMessage = "MASTER_DISCOVERY";

  MasterAnnouncer({
    this.message = discoveryMessage,
    Duration broadcastInterval = const Duration(seconds: 2),
    MasterBroadcastSender? broadcastSender,
    MasterAnnouncerTimerFactory? timerFactory,
  })  : _broadcastInterval = broadcastInterval,
        _broadcastSender = broadcastSender ?? _sendUdpBroadcast,
        _timerFactory = timerFactory ?? Timer.periodic;

  final String message; // Message for master presence
  final Duration _broadcastInterval;
  final MasterBroadcastSender _broadcastSender;
  final MasterAnnouncerTimerFactory _timerFactory;
  Timer? _timer;
  bool _isBroadcasting = false; // Flag to track if broadcasting is active

  /// Starts broadcasting the master’s IP periodically using UDP.
  void startBroadcasting() {
    if (_isBroadcasting) {
      LogService.instance
          .registerLog("MasterAnnouncer is already broadcasting.");
      return;
    }
    _isBroadcasting = true;
    _timer = _timerFactory(_broadcastInterval, (_) {
      unawaited(_broadcastPresence());
    });
  }

  Future<void> _broadcastPresence() async {
    try {
      await _broadcastSender(message, broadcastPort);
      if (message != discoveryMessage) {
        LogService.instance.registerLog("Broadcast message sent: $message");
      }
    } catch (e) {
      LogService.instance.registerLog("Error during broadcasting: $e");
    }
  }

  static Future<void> _sendUdpBroadcast(String message, int port) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(
        message.codeUnits,
        InternetAddress("255.255.255.255"),
        port,
      );
    } finally {
      socket?.close();
    }
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
    LogService.instance
        .registerLog("Stopped broadcasting master discovery message.");
  }
}
