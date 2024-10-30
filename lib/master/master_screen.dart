import 'package:flutter/material.dart';
import 'master_server.dart';

/// MasterScreen - Main UI for the master device to control slave cameras.
class MasterScreen extends StatefulWidget {
  @override
  _MasterScreenState createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  final MasterServer _server = MasterServer();

  @override
  void initState() {
    super.initState();
    _server.startServer();
  }

  @override
  void dispose() {
    _server.stopServer();
    super.dispose();
  }

  /// Sends the start camera command to all connected slave devices.
  void _startCamera() {
    _server.sendCommand('startCamera');
  }

  /// Sends the stop camera command to all connected slave devices.
  void _stopCamera() {
    _server.sendCommand('stopCamera');
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
            ElevatedButton(
              onPressed: _startCamera,
              child: Text("Start Camera on Slaves"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _stopCamera,
              child: Text("Stop Camera on Slaves"),
            ),
          ],
        ),
      ),
    );
  }
}
