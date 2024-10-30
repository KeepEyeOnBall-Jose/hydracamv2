import 'package:flutter/material.dart';
import 'slave_client.dart';
import 'master_discovery.dart';

class SlaveScreen extends StatefulWidget {
  @override
  _SlaveScreenState createState() => _SlaveScreenState();
}

class _SlaveScreenState extends State<SlaveScreen> {
  SlaveClient? _client;
  bool isConnected = false;
  String statusMessage = "Waiting for camera commands...";

  @override
  void initState() {
    super.initState();

    MasterDiscovery(onMasterDiscovered: (masterIp) {
      if (!isConnected) {
        print("Connecting to master at IP: $masterIp");
        // Log para confirmar la URL exacta de conexión antes de instanciar `SlaveClient`
        print("Full WebSocket URL being used: ws://$masterIp:4040");

        // Confirmar que `_client` esté usando el path correcto
        _client = SlaveClient('ws://$masterIp:4040/ws');
        _client?.connect();
        setState(() {
          isConnected = true;
          statusMessage = "Connected to master at $masterIp";
        });
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(statusMessage),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  statusMessage = "Photo taken";
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Photo taken")),
                );
              },
              child: Text("Simulate Take Photo"),
            ),
          ],
        ),
      ),
    );
  }
}
