import 'package:flutter/material.dart';
import 'slave_client.dart';
import 'master_discovery.dart';

/// SlaveScreen - Main UI for slave devices, listens for master commands.
class SlaveScreen extends StatefulWidget {
  @override
  _SlaveScreenState createState() => _SlaveScreenState();
}

class _SlaveScreenState extends State<SlaveScreen> {
  SlaveClient? _client;

  @override
  void initState() {
    super.initState();

    // Start listening for master IP using MasterDiscovery
    MasterDiscovery(onMasterDiscovered: (masterIp) {
      print("Connecting to master at IP: $masterIp");
      _client = SlaveClient('ws://$masterIp:4040');
      _client?.connect();
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
