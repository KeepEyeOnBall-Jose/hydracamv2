import 'package:flutter/material.dart';
import '../models/CapturedPhoto.dart';
import 'master_server.dart';
import 'master_announcer.dart';
import 'dart:io';

/// MasterScreen - Main UI for the master device to control slave cameras.
class MasterScreen extends StatefulWidget {
  @override
  _MasterScreenState createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  final MasterServer _server = MasterServer();
  final MasterAnnouncer _announcer = MasterAnnouncer(); // Broadcast announcer
  int connectedClients = 0; // To display connected clients count
  List<CapturedPhoto> get photos => _server.currentSession?.capturedPhotos ?? [];

  @override
  void initState() {
    super.initState();
    _server.onClientCountChange = (count) {
      setState(() {
        connectedClients = count;
      });
    };
    _server.onPhotoReceived = (photo) {
      setState(() {}); // Update screen when photo is received
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
        title: Text("HydraCam - Master Control"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Connected clients: $connectedClients"),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                _server.startNewSession();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("New capture session started")),
                );
              },
              child: Text("Start New Session"),
            ),
            ElevatedButton(
              onPressed: () {
                _server.endCurrentSession();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Capture session ended")),
                );
              },
              child: Text("End Current Session"),
            ),
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
            Expanded(
              child: ListView.builder(
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return ListTile(
                    leading: Image.file(File(photo.photoPath), width: 50, height: 50),
                    title: Text("Photo from Slave: ${photo.slaveDeviceId}"),
                    subtitle: Text(
                      "Captured: ${photo.captureDate}\nReceived: ${photo.receivedDate}",
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
