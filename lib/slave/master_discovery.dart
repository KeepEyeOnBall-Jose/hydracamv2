import 'dart:io';

import 'package:flutter/foundation.dart';

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
    if (kDebugMode) {
      print("Listening for master broadcast on port $broadcastPort...");
    }

    // Get current IP to avoid connecting to myself
    final localIp = await _getLocalIp();

    _socket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket?.receive();
        if (datagram != null) {
          final message = String.fromCharCodes(datagram.data);
          print("Received broadcast message: $message from ${datagram.address.address}");
          if (message == "MASTER_DISCOVERY") {

            final masterIp = datagram.address.address;

            // Avoid connecting to myself
            if (masterIp == localIp) {
              if (kDebugMode) {
                print("WARNING!: Ignored self-broadcast from $masterIp");
              }
              return; // Ignore if it is local IP
            }

            if (kDebugMode) {
              print("Master discovered at IP: $masterIp");
            }
            onMasterDiscovered(masterIp);
          }
        }
      }
    });
  }

  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error retrieving local IP: $e");
      }
    }
    return InternetAddress.anyIPv4.address;
  }


  /// Stops listening for the master broadcast message and closes the socket.
  Future<void> stopListening() async {
    if (_socket != null) {
      _socket?.close();
      _socket = null;
      if (kDebugMode) {
        print("Stopped listening for master broadcast.");
      }
    }
  }
}
