import 'package:flutter/material.dart';
import 'slave_client.dart';
import 'master_discovery.dart';

class SlaveScreen extends StatefulWidget {
  @override
  _SlaveScreenState createState() => _SlaveScreenState();
}

class _SlaveScreenState extends State<SlaveScreen> {
  SlaveClient? _client;
  bool isConnected = false; // Track if already connected

  @override
  void initState() {
    super.initState();

    // Start listening for master's broadcast and connect only once
    MasterDiscovery(onMasterDiscovered: (masterIp) {
      if (!isConnected) { // Check if not connected
        print("Connecting to master at IP: $masterIp");
        _client = SlaveClient('ws://$masterIp:4040');
        _client?.connect();
        isConnected = true; // Update connection status
      }
    }).startListening();
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("SportCamSync - Slave Device"),
      ),
      body: Center(
        child: Text("Waiting for camera commands..."),
      ),
    );
  }
}
