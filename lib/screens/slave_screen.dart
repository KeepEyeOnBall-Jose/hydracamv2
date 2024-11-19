import 'dart:io';
import 'package:flutter/material.dart';
import '../services/device_service.dart';
import '../slave/slave_client.dart';
import '../slave/master_discovery.dart';

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
        _client = SlaveClient(
          'ws://$masterIp:4040/ws',
          onPhotoTaken: (path) {
            setState(() {
              statusMessage = "Photo taken!";
            });

            // Show the taken photo in a modal
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text("Photo Taken"),
                content: Image.file(File(path)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Close"),
                  ),
                ],
              ),
            );
            // Automatically close after 5 seconds
            Future.delayed(Duration(seconds: 5), () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            });
          },
        );
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
        title: Text("HydraCam - Slave Device"),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () async {
              Map<String, dynamic> deviceInfo = await DeviceIdService.getDeviceInfo();
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text("Device Info"),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: deviceInfo.entries.map((entry) {
                        return Text('${entry.key}: ${entry.value}');
                      }).toList(),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Close"),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(statusMessage),
            SizedBox(height: 20)
            // Here camera preview or something
            ,
          ],
        ),
      ),
    );
  }
}
