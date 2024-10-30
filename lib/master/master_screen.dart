import 'package:flutter/material.dart';
import 'master_server.dart';
import 'master_announcer.dart';

/// MasterScreen - Main UI for the master device to control slave cameras.
class MasterScreen extends StatefulWidget {
  @override
  _MasterScreenState createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  final MasterServer _server = MasterServer();
  final MasterAnnouncer _announcer = MasterAnnouncer(); // Broadcast announcer
  int connectedClients = 0; // To display connected clients count

  @override
  void initState() {
    super.initState();
    _server.onClientCountChange = (count) {
      setState(() {
        connectedClients = count;
      });
    };
    _server.startServer();
    _announcer.startBroadcasting();
  }

  @override
  void dispose() {
    _server.stopServer();
    _announcer.stopBroadcasting();
    super.dispose();
  }

  /// Sends the start camera command to all connected slave devices.
  void _startCamera() {
    _server.sendCommand('startCamera');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Start camera command sent to slaves")),
    );
  }

  /// Sends the simulated take photo command to all connected slave devices.
  void _simulateTakePhoto() {
    _server.sendCommand('simulateTakePhoto');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Simulate photo command sent")),
    );
  }

  /// Sends the real take photo command to all connected slave devices.
  void _takeRealPhoto() {
    _server.sendCommand('takePhoto');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Real photo command sent")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("SportCamSync - Master Control"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Connected clients: $connectedClients"),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startCamera,
              child: Text("Start Camera on Slaves"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _simulateTakePhoto,
              child: Text("Simulate Take Photo on Slaves"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _takeRealPhoto,
              child: Text("Take Real Photo on Slaves"),
            ),
          ],
        ),
      ),
    );
  }
}
