import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../globals.dart';
import '../services/device_service.dart';
import '../slave/slave_client.dart';
import '../slave/master_discovery.dart';
import 'master_screen.dart';

class SlaveScreen extends StatefulWidget {

  // Mode that controls if we entered here manually or on app init.
  // If is auto mode, after some time without finding master will move automatically to master screen
  final bool isAutoMode;
  const SlaveScreen({super.key, this.isAutoMode = false}); // Default is manual mode

  @override
  _SlaveScreenState createState() => _SlaveScreenState();
}

class _SlaveScreenState extends State<SlaveScreen> {
  SlaveClient? _client;
  bool isConnected = false;
  String statusMessage = "Waiting for camera commands...";
  Timer? autoModeTimer; // Timer for auto mode logic

  @override
  void initState() {
    super.initState();

    MasterDiscovery(onMasterDiscovered: (masterIp) {
      if (!isConnected) {
        if (kDebugMode) {
          print("Connecting to master at IP: $masterIp");
        }
        _client = SlaveClient(
          'ws://$masterIp:4040/ws',
          onPhotoTaken: (path) {
            setState(() {
              statusMessage = "Photo taken!";
            });
            if (kDebugMode) {
              print("Photo taken!!!");
            }

            // Flag to track if the dialog is still open
            bool isDialogOpen = true;

            // Show the taken photo in a modal
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Photo Taken"),
                content: Image.file(File(path)),
                actions: [
                  TextButton(
                    onPressed: () {
                      // Mark the dialog as closed and manually close it
                      isDialogOpen = false;
                      Navigator.pop(context);
                    },
                    child: const Text("Close"),
                  ),
                ],
              ),
            ).then((_) {
              // When the dialog is closed (manually or automatically), mark it as closed
              isDialogOpen = false;
            });

            // Automatically close after N seconds
            Future.delayed(Duration(seconds: secondsToClosePhoto), () {
              if (isDialogOpen && Navigator.canPop(context)) {
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

        if (widget.isAutoMode) {
          autoModeTimer?.cancel(); // Stop auto mode if master is found
        }
      }
    }).startListening();

    if (widget.isAutoMode) {
      // Automatically transition to MasterScreen if no master is found
      autoModeTimer = Timer(Duration(seconds: timeToStopSearching), () {
        if (!isConnected) {
          if (kDebugMode) {
            print("No master found, switching to Master mode.");
          }
          _transitionToMasterScreen();
        }
      });
    }

  }

  void _transitionToMasterScreen() {
    // Stop slave client
    _client?.disconnect();
    MasterDiscovery(onMasterDiscovered: (masterIp) {}).stopListening();

    // Change to MasterScreen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MasterScreen()),
    );
  }


  @override
  void dispose() {
    _client?.disconnect();
    autoModeTimer?.cancel();
    MasterDiscovery(onMasterDiscovered: (masterIp) {}).stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("HydraCam - Slave Device"),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () async {
              Map<String, dynamic> deviceInfo = await DeviceIdService.getDeviceInfo();
              showDialog( //TODO rewrite to better use context
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
