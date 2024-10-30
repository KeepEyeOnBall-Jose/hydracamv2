import 'package:flutter/material.dart';
import 'slave_client.dart';

/// SlaveScreen - Main UI for slave devices, listens for master commands.
class SlaveScreen extends StatefulWidget {
  @override
  _SlaveScreenState createState() => _SlaveScreenState();
}

class _SlaveScreenState extends State<SlaveScreen> {
  final SlaveClient _client = SlaveClient('ws://192.168.4.1:4040'); // Replace with master IP

  @override
  void initState() {
    super.initState();
    _client.connect();
  }

  @override
  void dispose() {
    _client.disconnect();
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
